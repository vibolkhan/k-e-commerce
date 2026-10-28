import { assertEquals, assertRejects } from "@std/assert";
import { BadRequest, Unauthorized } from "./errors.ts";
import {
  type CatalogDeps,
  checkProduct,
  type FieldError,
  manageCatalog,
  type ProductInput,
} from "./catalog_flows.ts";
import type { StaffMember, StaffRole } from "./staff_flows.ts";

const CATEGORY = "11111111-1111-4111-8111-111111111111";
const PRODUCT = "22222222-2222-4222-8222-222222222222";

// In-memory twin of auth, staff and the catalog SQL functions.
class FakeWorld implements CatalogDeps {
  tokens = new Map([
    ["t-visal", "u-visal"],
    ["t-chenda", "u-chenda"],
    ["t-dalin", "u-dalin"],
    ["t-old", "u-old"],
  ]);
  members = new Map<string, StaffMember>([
    ["u-visal", member("u-visal", "catalog", "active")],
    ["u-chenda", member("u-chenda", "super_admin", "active")],
    ["u-dalin", member("u-dalin", "sales", "active")],
    ["u-old", member("u-old", "catalog", "removed")],
  ]);
  saved: { actor: string; product: ProductInput }[] = [];
  statuses: { actor: string; ids: string[]; status: string }[] = [];
  moved: { actor: string; ids: string[]; category: string }[] = [];
  nextSave: Record<string, unknown> = { status: "saved", id: PRODUCT };

  userIdFor(authorization: string | null) {
    const token = authorization?.replace(/^Bearer\s+/i, "") ?? "";
    return Promise.resolve(this.tokens.get(token) ?? null);
  }
  member(profileId: string) {
    return Promise.resolve(this.members.get(profileId) ?? null);
  }
  saveProduct(actor: string, product: ProductInput) {
    this.saved.push({ actor, product });
    return Promise.resolve(this.nextSave);
  }
  setStatus(actor: string, ids: string[], status: "active" | "draft" | "archived") {
    this.statuses.push({ actor, ids, status });
    return Promise.resolve(ids.length);
  }
  setCategory(actor: string, ids: string[], category: string) {
    this.moved.push({ actor, ids, category });
    return Promise.resolve(ids.length);
  }
}

function member(id: string, role: StaffRole, status: StaffMember["status"]): StaffMember {
  return { profile_id: id, full_name: id, email: null, phone: null, staff_role: role, status };
}

function req(token?: string) {
  return new Request("http://local/catalog-manage", {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
}

function product(overrides: Record<string, unknown> = {}) {
  return {
    category_id: CATEGORY,
    name: { en: "  Studio Monitor ", km: "" },
    description: { en: "Near-field monitor." },
    highlights: [{ en: "5 inch woofer" }, { en: "", km: "" }],
    specs: [{ name: "Power", value: "50 W" }, { name: "", value: "" }],
    tags: ["New", "New", " "],
    options: [{ name: { en: "Colour" }, values: ["Black", "White", "Black"] }],
    status: "active",
    rfq_enabled: true,
    rfq_min_qty: 5,
    variants: [
      { sku: "MON-BLK", attributes: { Colour: "Black" }, price_cents: 12900, initial_qty: 8 },
      { sku: "MON-WHT", attributes: { Colour: "White" }, price_cents: 12900 },
    ],
    images: [{ path: "products/p/1.jpg", alt: { en: "Front" }, variant_sku: "MON-BLK" }],
    ...overrides,
  };
}

function errorsOf(raw: unknown): FieldError[] {
  const result = checkProduct(raw);
  return "errors" in result ? result.errors : [];
}

Deno.test("a missing or invalid session is 401", async () => {
  const world = new FakeWorld();
  await assertRejects(() => manageCatalog(world, { action: "save" }, req()), Unauthorized);
  await assertRejects(() => manageCatalog(world, { action: "save" }, req("nope")), Unauthorized);
});

Deno.test("only active catalog staff and super admins may change the catalogue", async () => {
  const world = new FakeWorld();
  for (const token of ["t-dalin", "t-old"]) {
    assertEquals(
      await manageCatalog(world, { action: "save", product: product() }, req(token)),
      { status: "forbidden" },
    );
  }
  assertEquals(world.saved.length, 0);
  assertEquals(
    await manageCatalog(world, { action: "save", product: product() }, req("t-chenda")),
    { status: "saved", id: PRODUCT },
  );
});

Deno.test("save cleans the product and saves it as the caller", async () => {
  const world = new FakeWorld();
  const result = await manageCatalog(world, { action: "save", product: product() }, req("t-visal"));
  assertEquals(result, { status: "saved", id: PRODUCT });
  const [{ actor, product: saved }] = world.saved;
  assertEquals(actor, "u-visal");
  assertEquals(saved.name, { en: "Studio Monitor" });
  assertEquals(saved.highlights, [{ en: "5 inch woofer" }]);
  assertEquals(saved.specs, [{ name: "Power", value: "50 W" }]);
  assertEquals(saved.tags, ["New"]);
  assertEquals(saved.options[0].values, ["Black", "White"]);
  assertEquals(saved.variants[0].initial_qty, 8);
  assertEquals(saved.rfq_min_qty, 5);
  assertEquals(saved.same_day, true);
});

Deno.test("opening stock is only sent for new variants", () => {
  const result = checkProduct(product({
    variants: [{ id: PRODUCT, sku: "MON-BLK", price_cents: 100, initial_qty: 4 }],
  }));
  assertEquals("product" in result && result.product.variants[0].initial_qty, undefined);
});

Deno.test("save lists every problem with the product", () => {
  assertEquals(
    errorsOf(product({
      name: { en: " ", km: "ឈ្មោះ" },
      category_id: "",
      rfq_min_qty: null,
      variants: [
        { sku: "bad sku", price_cents: 0 },
        { sku: "OK-1", price_cents: 12.5 },
        { sku: "ok-1", price_cents: 100, compare_at_cents: 90 },
      ],
      images: [{ path: "elsewhere/1.jpg", alt: { en: " " }, variant_sku: "NOPE" }],
    })),
    [
      { field: "name.en", code: "required" },
      { field: "category_id", code: "required" },
      { field: "variants.0.sku", code: "invalid" },
      { field: "variants.0.price_cents", code: "invalid" },
      { field: "variants.1.price_cents", code: "invalid" },
      { field: "variants.2.compare_at_cents", code: "invalid" },
      { field: "variants.2.sku", code: "duplicate" },
      { field: "rfq_min_qty", code: "required" },
      { field: "images.0.path", code: "invalid" },
      { field: "images.0.alt", code: "required" },
      { field: "images.0.variant_sku", code: "invalid" },
    ],
  );
});

Deno.test("a product needs at least one variant and at most 10 images", () => {
  const images = Array.from({ length: 11 }, (_, i) => ({
    path: `products/p/${i}.jpg`,
    alt: { en: `Photo ${i}` },
  }));
  assertEquals(errorsOf(product({ variants: [], images })), [
    { field: "variants", code: "required" },
    { field: "images", code: "too_many" },
  ]);
});

Deno.test("text limits", () => {
  assertEquals(errorsOf(product({ description: { km: "ក".repeat(1001) } })), [
    { field: "description.km", code: "too_long" },
  ]);
});

Deno.test("database refusals become outcomes", async () => {
  const world = new FakeWorld();
  world.nextSave = { status: "sku_taken", sku: "MON-BLK" };
  assertEquals(
    await manageCatalog(world, { action: "save", product: product() }, req("t-visal")),
    { status: "sku_taken", sku: "MON-BLK" },
  );
  world.nextSave = { status: "not_found" };
  assertEquals(
    await manageCatalog(
      world,
      { action: "save", product: product({ id: PRODUCT }) },
      req("t-visal"),
    ),
    { status: "not_found" },
  );
  world.nextSave = { status: "invalid", field: "category" };
  assertEquals(
    await manageCatalog(world, { action: "save", product: product() }, req("t-visal")),
    { status: "invalid", errors: [{ field: "category", code: "invalid" }] },
  );
});

Deno.test("archive and restore one product; archive or move many", async () => {
  const world = new FakeWorld();
  assertEquals(
    await manageCatalog(world, { action: "archive", id: PRODUCT }, req("t-visal")),
    { status: "updated", count: 1 },
  );
  await manageCatalog(world, { action: "restore", id: PRODUCT }, req("t-visal"));
  await manageCatalog(world, { action: "bulk_archive", ids: [PRODUCT, PRODUCT] }, req("t-visal"));
  assertEquals(world.statuses.map((s) => [s.status, s.ids.length]), [
    ["archived", 1],
    ["draft", 1],
    ["archived", 1],
  ]);
  await manageCatalog(
    world,
    { action: "bulk_category", ids: [PRODUCT], category_id: CATEGORY },
    req("t-chenda"),
  );
  assertEquals(world.moved, [{ actor: "u-chenda", ids: [PRODUCT], category: CATEGORY }]);
});

Deno.test("malformed requests are 400", async () => {
  const world = new FakeWorld();
  await assertRejects(() => manageCatalog(world, { action: "delete" }, req("t-visal")), BadRequest);
  await assertRejects(
    () => manageCatalog(world, { action: "archive", id: "x" }, req("t-visal")),
    BadRequest,
  );
  await assertRejects(
    () => manageCatalog(world, { action: "bulk_archive", ids: [] }, req("t-visal")),
    BadRequest,
  );
  await assertRejects(
    () => manageCatalog(world, { action: "save", product: [] }, req("t-visal")),
    BadRequest,
  );
});
