// CSV product import behind the catalog-import Edge Function (F09, ADM-02;
// A-05d "Import products": upload -> match columns -> review & import).
//
// One row is one variant. Rows that share a `handle` become variants of one
// product; without a handle every row is its own product. Rows with errors
// are skipped and reported; the rest are imported as drafts (they have no
// images yet) in one transaction.
//
// Body: { action: "preview" | "commit", csv: string, mapping: { [column]: Field } }.
// `preview` only checks; `commit` checks again and imports. Row numbers are
// spreadsheet rows: the header is row 1.

import { parse } from "@std/csv";
import { BadRequest } from "./errors.ts";
import {
  type CatalogDeps,
  isObject,
  LIMITS,
  type ProductInput,
  requireEditor,
  SKU_PATTERN,
} from "./catalog_flows.ts";

export const IMPORT_FIELDS = [
  "name_en",
  "name_km",
  "description_en",
  "description_km",
  "brand",
  "category",
  "sku",
  "barcode",
  "price_usd",
  "qty",
  "tags",
  "handle",
  "variant",
  "ignore",
] as const;
export type ImportField = typeof IMPORT_FIELDS[number];

export const MAX_ROWS = 5000;
export const MAX_BYTES = 2 * 1024 * 1024;

export type RowErrorCode =
  | "name_missing"
  | "sku_missing"
  | "sku_invalid"
  | "sku_duplicate"
  | "sku_exists"
  | "price_missing"
  | "price_invalid"
  | "qty_invalid"
  | "category_missing"
  | "category_unknown"
  | "too_long";

export interface RowError {
  row: number;
  code: RowErrorCode;
  /** The offending value, for the message ("unknown category "Gadgets""). */
  value?: string;
}

export interface Category {
  id: string;
  slug: string;
  name_en: string;
  parent_name_en: string | null;
}

export interface ImportDeps extends Pick<CatalogDeps, "userIdFor" | "member"> {
  categories(): Promise<Category[]>;
  /** The SKUs from this list that already exist. */
  existingSkus(skus: string[]): Promise<string[]>;
  /** catalog_import: all products in one transaction. */
  importProducts(actorId: string, products: ProductInput[]): Promise<number>;
}

export type ImportResult =
  | {
    status: "preview";
    rows: number;
    valid: number;
    products: number;
    errors: RowError[];
  }
  | { status: "imported"; products: number; variants: number; skipped: number; errors: RowError[] }
  | { status: "empty" }
  | { status: "too_large" }
  | { status: "unreadable" }
  | { status: "no_mapping"; missing: ImportField[] }
  | { status: "forbidden" };

/** Fields a mapping must include. */
const REQUIRED: ImportField[] = ["name_en", "sku", "price_usd", "category"];

/** The whole catalog-import function. */
export async function importCatalog(
  deps: ImportDeps,
  body: Record<string, unknown>,
  req: Request,
): Promise<ImportResult> {
  const callerId = await requireEditor(deps, req);
  if (!callerId) return { status: "forbidden" };

  const action = body.action;
  if (action !== "preview" && action !== "commit") {
    throw new BadRequest("action must be preview or commit");
  }
  if (typeof body.csv !== "string") throw new BadRequest("csv must be a string");
  const mapping = readMapping(body.mapping);

  if (new TextEncoder().encode(body.csv).length > MAX_BYTES) return { status: "too_large" };
  let table: string[][];
  try {
    table = parse(body.csv.replace(/^﻿/, ""), { skipFirstRow: false }) as string[][];
  } catch {
    return { status: "unreadable" };
  }
  const header = table[0]?.map((h) => h.trim()) ?? [];
  const rows = table.slice(1).filter((r) => r.some((cell) => cell.trim() !== ""));
  if (header.length === 0 || rows.length === 0) return { status: "empty" };
  if (rows.length > MAX_ROWS) return { status: "too_large" };

  const mapped = new Set(Object.values(mapping));
  const missing = REQUIRED.filter((f) => !mapped.has(f));
  if (missing.length > 0) return { status: "no_mapping", missing };

  const plan = await planImport(deps, header, rows, mapping);
  if (action === "preview") {
    return {
      status: "preview",
      rows: rows.length,
      valid: plan.variants,
      products: plan.products.length,
      errors: plan.errors,
    };
  }

  const imported = plan.products.length > 0
    ? await deps.importProducts(callerId, plan.products)
    : 0;
  return {
    status: "imported",
    products: imported,
    variants: plan.variants,
    skipped: rows.length - plan.variants,
    errors: plan.errors,
  };
}

function readMapping(value: unknown): Record<string, ImportField> {
  if (!isObject(value)) throw new BadRequest("mapping must be an object");
  const out: Record<string, ImportField> = {};
  const used = new Set<ImportField>();
  for (const [column, field] of Object.entries(value)) {
    if (!(IMPORT_FIELDS as readonly unknown[]).includes(field)) {
      throw new BadRequest(`unknown field for column ${column}`);
    }
    const f = field as ImportField;
    if (f !== "ignore" && used.has(f)) throw new BadRequest(`${f} is mapped twice`);
    used.add(f);
    out[column.trim()] = f;
  }
  return out;
}

interface Plan {
  products: ProductInput[];
  variants: number;
  errors: RowError[];
}

/** Checks every row and groups the good ones into products. */
export async function planImport(
  deps: Pick<ImportDeps, "categories" | "existingSkus">,
  header: string[],
  rows: string[][],
  mapping: Record<string, ImportField>,
): Promise<Plan> {
  const index = new Map<ImportField, number>();
  header.forEach((column, i) => {
    const field = mapping[column];
    if (field && field !== "ignore") index.set(field, i);
  });
  const cell = (row: string[], field: ImportField) => {
    const i = index.get(field);
    return i === undefined ? "" : (row[i] ?? "").trim();
  };

  const categories = categoryLookup(await deps.categories());
  const fileSkus = rows.map((r) => cell(r, "sku")).filter((s) => s !== "");
  const existing = new Set(
    (await deps.existingSkus([...new Set(fileSkus)])).map((s) => s.toUpperCase()),
  );
  const counts = new Map<string, number>();
  for (const sku of fileSkus) {
    counts.set(sku.toUpperCase(), (counts.get(sku.toUpperCase()) ?? 0) + 1);
  }

  const errors: RowError[] = [];
  const groups = new Map<string, ProductInput>();
  let variants = 0;

  rows.forEach((row, i) => {
    const rowNo = i + 2;
    const fail = (code: RowErrorCode, value?: string) =>
      errors.push(value === undefined ? { row: rowNo, code } : { row: rowNo, code, value });
    const before = errors.length;

    const handle = cell(row, "handle");
    const group = handle ? groups.get(handle.toLowerCase()) : undefined;

    const nameEn = cell(row, "name_en");
    if (!nameEn && !group) fail("name_missing");
    if (nameEn.length > LIMITS.name || cell(row, "name_km").length > LIMITS.name) fail("too_long");
    if (
      cell(row, "description_en").length > LIMITS.description ||
      cell(row, "description_km").length > LIMITS.description
    ) fail("too_long");

    const sku = cell(row, "sku");
    if (!sku) fail("sku_missing");
    else if (!SKU_PATTERN.test(sku)) fail("sku_invalid", sku);
    else if (existing.has(sku.toUpperCase())) fail("sku_exists", sku);
    else if ((counts.get(sku.toUpperCase()) ?? 0) > 1) fail("sku_duplicate", sku);

    const priceText = cell(row, "price_usd");
    const price = parsePriceCents(priceText);
    if (!priceText) fail("price_missing");
    else if (price === null) fail("price_invalid", priceText);

    const qtyText = cell(row, "qty");
    const qty = qtyText === "" ? 0 : Number(qtyText.replace(/,/g, ""));
    if (!(Number.isInteger(qty) && qty >= 0 && qty <= LIMITS.maxQty)) fail("qty_invalid", qtyText);

    const categoryText = cell(row, "category");
    const categoryId = categoryText ? categories(categoryText) : undefined;
    if (!categoryText && !group) fail("category_missing");
    else if (categoryText && !categoryId) fail("category_unknown", categoryText);

    if (errors.length > before) return;

    const variant = {
      sku,
      ...(cell(row, "barcode") ? { barcode: cell(row, "barcode") } : {}),
      attributes: parseAttributes(cell(row, "variant")),
      active: true,
      price_cents: price!,
      ...(qty > 0 ? { initial_qty: qty } : {}),
    };
    variants++;

    if (group) {
      group.variants.push(variant);
      return;
    }
    const nameKm = cell(row, "name_km");
    const descEn = cell(row, "description_en");
    const descKm = cell(row, "description_km");
    const brand = cell(row, "brand");
    const product: ProductInput = {
      category_id: categoryId!,
      ...(brand ? { brand } : {}),
      name: { en: nameEn, ...(nameKm ? { km: nameKm } : {}) },
      description: { ...(descEn ? { en: descEn } : {}), ...(descKm ? { km: descKm } : {}) },
      highlights: [],
      specs: [],
      tags: splitList(cell(row, "tags")).slice(0, LIMITS.tags),
      options: [],
      status: "draft",
      is_best_seller: false,
      same_day: true,
      rfq_enabled: false,
      rfq_multiple: 1,
      variants: [variant],
      images: [],
    };
    groups.set(handle ? handle.toLowerCase() : `#row${rowNo}`, product);
  });

  const products = [...groups.values()].map(withOptions);
  return { products, variants, errors };
}

/** "Black", "$49", "49.00", "1,250.5" -> cents; null when not a positive amount. */
export function parsePriceCents(text: string): number | null {
  const clean = text.replace(/^\s*(US)?\$\s*/i, "").replace(/\s*USD\s*$/i, "").replace(/,/g, "");
  if (!/^\d+(\.\d{1,2})?$/.test(clean)) return null;
  const cents = Math.round(Number(clean) * 100);
  return cents >= 1 && cents <= LIMITS.maxPriceCents ? cents : null;
}

/** "Colour: Black; Size: M" -> {"Colour": "Black", "Size": "M"}; "Black" -> {"Option": "Black"}. */
export function parseAttributes(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const part of text.split(/[;|]/)) {
    const [key, ...rest] = part.split(":");
    const value = rest.join(":").trim();
    if (rest.length === 0) {
      if (key.trim()) out["Option"] = key.trim();
    } else if (key.trim() && value) {
      out[key.trim()] = value;
    }
  }
  return out;
}

function splitList(text: string): string[] {
  return [...new Set(text.split(/[,;|]/).map((t) => t.trim()).filter((t) => t !== ""))];
}

/** Options on a product follow its variants' attributes (A-05b Options card). */
function withOptions(product: ProductInput): ProductInput {
  const values = new Map<string, string[]>();
  for (const v of product.variants) {
    for (const [name, value] of Object.entries(v.attributes)) {
      const list = values.get(name) ?? [];
      if (!list.includes(value)) list.push(value);
      values.set(name, list);
    }
  }
  return {
    ...product,
    options: [...values.entries()].slice(0, LIMITS.options).map(([name, vals]) => ({
      name: { en: name },
      values: vals,
    })),
  };
}

/** Finds a category by slug, English name or "Parent > Child", ignoring case. */
export function categoryLookup(categories: Category[]): (text: string) => string | undefined {
  const byKey = new Map<string, string>();
  const norm = (s: string) => s.trim().toLowerCase().replace(/\s+/g, " ");
  for (const c of categories) {
    byKey.set(norm(c.slug), c.id);
    if (c.parent_name_en) byKey.set(norm(`${c.parent_name_en} > ${c.name_en}`), c.id);
  }
  // Plain names last, so a slug or full path wins over a same-named child.
  for (const c of categories) {
    if (!byKey.has(norm(c.name_en))) byKey.set(norm(c.name_en), c.id);
  }
  return (text) => byKey.get(norm(text.replace(/\s*[›/]\s*/g, " > ")));
}
