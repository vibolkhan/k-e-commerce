import { assertEquals, assertRejects } from "@std/assert";
import { BadRequest } from "./errors.ts";
import type { ProductInput } from "./catalog_flows.ts";
import {
  type Category,
  categoryLookup,
  importCatalog,
  type ImportDeps,
  parseAttributes,
  parsePriceCents,
} from "./import_flows.ts";
import type { StaffMember } from "./staff_flows.ts";

const CATEGORIES: Category[] = [
  { id: "c-elec", slug: "electronics", name_en: "Electronics", parent_name_en: null },
  { id: "c-audio", slug: "audio", name_en: "Audio", parent_name_en: "Electronics" },
  { id: "c-kitchen", slug: "kitchen", name_en: "Kitchen", parent_name_en: null },
];

class FakeWorld implements ImportDeps {
  existing = ["MUG-4-SND"];
  imported: { actor: string; products: ProductInput[] }[] = [];
  userIdFor(authorization: string | null) {
    return Promise.resolve(
      authorization === "Bearer t-visal" ? "u-visal" : authorization ? "u-dalin" : null,
    );
  }
  member(id: string): Promise<StaffMember> {
    return Promise.resolve({
      profile_id: id,
      full_name: id,
      email: null,
      phone: null,
      staff_role: id === "u-visal" ? "catalog" : "sales",
      status: "active",
    });
  }
  categories() {
    return Promise.resolve(CATEGORIES);
  }
  existingSkus(skus: string[]) {
    return Promise.resolve(skus.filter((s) => this.existing.includes(s)));
  }
  importProducts(actor: string, products: ProductInput[]) {
    this.imported.push({ actor, products });
    return Promise.resolve(products.length);
  }
}

const req = (token = "t-visal") =>
  new Request("http://local/catalog-import", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });

const MAPPING = {
  name: "name_en",
  name_km: "name_km",
  sku: "sku",
  price_usd: "price_usd",
  qty: "qty",
  category: "category",
  handle: "handle",
  variant: "variant",
  supplier_code: "ignore",
};

const CSV = [
  "name,name_km,sku,price_usd,qty,category,handle,variant,supplier_code",
  "Studio Monitor,,MON-BLK,$129.00,8,audio,mon,Colour: Black,S-1",
  ",,MON-WHT,129,0,,mon,Colour: White,S-2",
  'Kettle,កំសៀវ,KET-1,"1,250.50",,Kitchen,,,S-3',
  "No price,,NP-1,,1,audio,,,S-4",
  "Mug copy,,MUG-4-SND,5,1,kitchen,,,S-5",
  "Gadget,,GAD-1,5,1,Gadgets,,,S-6",
  "Twice,,DUP-1,5,1,audio,,,S-7",
  "Twice again,,dup-1,5,-2,audio,,,S-8",
  "",
].join("\n");

Deno.test("preview groups rows into products and reports bad rows", async () => {
  const world = new FakeWorld();
  const result = await importCatalog(
    world,
    { action: "preview", csv: CSV, mapping: MAPPING },
    req(),
  );
  assertEquals(result, {
    status: "preview",
    rows: 8,
    valid: 3,
    products: 2,
    errors: [
      { row: 5, code: "price_missing" },
      { row: 6, code: "sku_exists", value: "MUG-4-SND" },
      { row: 7, code: "category_unknown", value: "Gadgets" },
      { row: 8, code: "sku_duplicate", value: "DUP-1" },
      { row: 9, code: "sku_duplicate", value: "dup-1" },
      { row: 9, code: "qty_invalid", value: "-2" },
    ],
  });
  assertEquals(world.imported, []);
});

Deno.test("commit imports the good rows as drafts, as the caller", async () => {
  const world = new FakeWorld();
  const result = await importCatalog(
    world,
    { action: "commit", csv: CSV, mapping: MAPPING },
    req(),
  );
  assertEquals(result.status, "imported");
  assertEquals(result.status === "imported" && [result.products, result.variants, result.skipped], [
    2,
    3,
    5,
  ]);
  const [{ actor, products }] = world.imported;
  assertEquals(actor, "u-visal");
  const [monitor, kettle] = products;
  assertEquals(monitor.status, "draft");
  assertEquals(monitor.category_id, "c-audio");
  assertEquals(monitor.variants.map((v) => [v.sku, v.price_cents, v.initial_qty]), [
    ["MON-BLK", 12900, 8],
    ["MON-WHT", 12900, undefined],
  ]);
  assertEquals(monitor.options, [{ name: { en: "Colour" }, values: ["Black", "White"] }]);
  assertEquals(kettle.name, { en: "Kettle", km: "កំសៀវ" });
  assertEquals(kettle.variants[0].price_cents, 125050);
  assertEquals(kettle.category_id, "c-kitchen");
});

Deno.test("the file must map the required fields and stay within limits", async () => {
  const world = new FakeWorld();
  assertEquals(
    await importCatalog(
      world,
      { action: "preview", csv: CSV, mapping: { name: "name_en" } },
      req(),
    ),
    { status: "no_mapping", missing: ["sku", "price_usd", "category"] },
  );
  assertEquals(
    await importCatalog(world, { action: "preview", csv: "name,sku\n", mapping: MAPPING }, req()),
    { status: "empty" },
  );
  const big = "name,sku\n" + "x,y\n".repeat(5001);
  assertEquals(
    await importCatalog(world, { action: "preview", csv: big, mapping: MAPPING }, req()),
    { status: "too_large" },
  );
  assertEquals(
    await importCatalog(world, { action: "preview", csv: 'a,"b\n1,2', mapping: MAPPING }, req()),
    { status: "unreadable" },
  );
});

Deno.test("only catalog editors import; bad bodies are 400", async () => {
  const world = new FakeWorld();
  assertEquals(
    await importCatalog(world, { action: "commit", csv: CSV, mapping: MAPPING }, req("t-dalin")),
    { status: "forbidden" },
  );
  await assertRejects(
    () => importCatalog(world, { action: "go", csv: CSV, mapping: MAPPING }, req()),
    BadRequest,
  );
  await assertRejects(
    () =>
      importCatalog(world, { action: "preview", csv: CSV, mapping: { a: "sku", b: "sku" } }, req()),
    BadRequest,
  );
  await assertRejects(
    () => importCatalog(world, { action: "preview", csv: CSV, mapping: { a: "colour" } }, req()),
    BadRequest,
  );
});

Deno.test("prices, attributes and categories in the formats people type", () => {
  assertEquals(parsePriceCents("49"), 4900);
  assertEquals(parsePriceCents("$49.5"), 4950);
  assertEquals(parsePriceCents("49.00 USD"), 4900);
  assertEquals(parsePriceCents("0"), null);
  assertEquals(parsePriceCents("49.999"), null);
  assertEquals(parsePriceCents("free"), null);
  assertEquals(parseAttributes("Colour: Black; Size: M"), { Colour: "Black", Size: "M" });
  assertEquals(parseAttributes("Black"), { Option: "Black" });
  const find = categoryLookup(CATEGORIES);
  assertEquals(find("Electronics › Audio"), "c-audio");
  assertEquals(find("electronics > audio"), "c-audio");
  assertEquals(find(" AUDIO "), "c-audio");
  assertEquals(find("Gadgets"), undefined);
});
