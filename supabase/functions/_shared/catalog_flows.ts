// Catalog management behind the catalog-manage Edge Function (F09, ADM-02,
// CAT-01, CAT-07; A-05 – A-05e).
//
// Pure logic: every side effect goes through `CatalogDeps`. The database
// backs the rules up: products, prices and stock are written by service-role
// functions that act as the staff member, so audit_logs records who changed
// each price (migrations/20261101000100_catalog_admin.sql).
//
// Body: { action: "save" | "archive" | "restore" | "bulk_archive" | "bulk_category", ... }.
// Every outcome is HTTP 200 with a `status`; a malformed body is 400 and a
// missing or invalid session is 401.

import { BadRequest, Unauthorized } from "./errors.ts";
import type { StaffMember } from "./staff_flows.ts";

/** Staff roles that may change the catalogue (A-14d matrix: Products "Full"). */
export const CATALOG_EDITORS = ["super_admin", "catalog"] as const;

export const LIMITS = {
  name: 120,
  description: 1000,
  highlights: 10,
  highlight: 120,
  specs: 30,
  specName: 40,
  specValue: 120,
  tags: 20,
  tag: 30,
  brand: 60,
  options: 3,
  optionValues: 30,
  variants: 100,
  images: 10,
  alt: 200,
  barcode: 64,
  maxPriceCents: 10_000_000, // $100,000
  maxQty: 1_000_000,
  maxRfqQty: 100_000,
  bulk: 200,
} as const;

export const SKU_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type I18n = { en?: string; km?: string };

export interface VariantInput {
  id?: string;
  sku: string;
  barcode?: string;
  attributes: Record<string, string>;
  active: boolean;
  price_cents: number;
  compare_at_cents?: number;
  initial_qty?: number;
}

export interface ImageInput {
  id?: string;
  path: string;
  alt: I18n;
  variant_sku?: string;
}

/** What catalog_save_product receives, cleaned and checked. */
export interface ProductInput {
  id?: string;
  category_id: string;
  slug?: string;
  brand?: string;
  name: I18n;
  description: I18n;
  highlights: I18n[];
  specs: { name: string; value: string }[];
  tags: string[];
  options: { name: I18n; values: string[] }[];
  status: "draft" | "active";
  is_best_seller: boolean;
  same_day: boolean;
  rfq_enabled: boolean;
  rfq_min_qty?: number;
  rfq_multiple: number;
  variants: VariantInput[];
  images: ImageInput[];
}

export interface FieldError {
  /** Dotted path, e.g. "name.en", "variants.2.sku", "images.0.alt". */
  field: string;
  code: "required" | "too_long" | "too_many" | "invalid" | "duplicate";
}

export interface CatalogDeps {
  /** The caller's user id from their `Authorization` header, null if not valid. */
  userIdFor(authorization: string | null): Promise<string | null>;
  member(profileId: string): Promise<StaffMember | null>;
  /** catalog_save_product: { status: "saved", id } | sku_taken | not_found | invalid. */
  saveProduct(actorId: string, product: ProductInput): Promise<Record<string, unknown>>;
  /** Number of products whose status changed. */
  setStatus(
    actorId: string,
    ids: string[],
    status: "active" | "draft" | "archived",
  ): Promise<number>;
  /** Number of products moved. */
  setCategory(actorId: string, ids: string[], categoryId: string): Promise<number>;
}

export type CatalogResult =
  | { status: "saved"; id: string }
  | { status: "updated"; count: number }
  | { status: "invalid"; errors: FieldError[] }
  | { status: "sku_taken"; sku: string }
  | { status: "not_found" }
  | { status: "forbidden" };

/** The whole catalog-manage function. */
export async function manageCatalog(
  deps: CatalogDeps,
  body: Record<string, unknown>,
  req: Request,
): Promise<CatalogResult> {
  const callerId = await requireEditor(deps, req);
  if (!callerId) return { status: "forbidden" };

  switch (body.action) {
    case "save":
      return await save(deps, callerId, body.product);
    case "archive":
      return await status(deps, callerId, [requiredId(body.id)], "archived");
    case "restore":
      return await status(deps, callerId, [requiredId(body.id)], "draft");
    case "bulk_archive":
      return await status(deps, callerId, ids(body.ids), "archived");
    case "bulk_category":
      return {
        status: "updated",
        count: await deps.setCategory(callerId, ids(body.ids), requiredId(body.category_id)),
      };
    default:
      throw new BadRequest("action must be save, archive, restore, bulk_archive or bulk_category");
  }
}

/** The caller's id when they are active catalog staff or a super admin. */
export async function requireEditor(
  deps: Pick<CatalogDeps, "userIdFor" | "member">,
  req: Request,
): Promise<string | null> {
  const callerId = await deps.userIdFor(req.headers.get("Authorization"));
  if (!callerId) throw new Unauthorized();
  const caller = await deps.member(callerId);
  const allowed = caller?.status === "active" &&
    (CATALOG_EDITORS as readonly string[]).includes(caller.staff_role);
  return allowed ? callerId : null;
}

async function save(deps: CatalogDeps, actorId: string, raw: unknown): Promise<CatalogResult> {
  const checked = checkProduct(raw);
  if ("errors" in checked) return { status: "invalid", errors: checked.errors };

  const result = await deps.saveProduct(actorId, checked.product);
  switch (result.status) {
    case "saved":
      return { status: "saved", id: String(result.id) };
    case "sku_taken":
      return { status: "sku_taken", sku: String(result.sku) };
    case "not_found":
      return { status: "not_found" };
    default:
      return {
        status: "invalid",
        errors: [{ field: String(result.field ?? "product"), code: "invalid" }],
      };
  }
}

async function status(
  deps: CatalogDeps,
  actorId: string,
  productIds: string[],
  to: "archived" | "draft",
): Promise<CatalogResult> {
  return { status: "updated", count: await deps.setStatus(actorId, productIds, to) };
}

function requiredId(value: unknown): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new BadRequest("id must be a uuid");
  }
  return value;
}

function ids(value: unknown): string[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > LIMITS.bulk) {
    throw new BadRequest(`ids must be 1 to ${LIMITS.bulk} product ids`);
  }
  return [...new Set(value.map(requiredId))];
}

// ---------------------------------------------------------------------------
// Product validation
// ---------------------------------------------------------------------------

/** Cleans a product from the editor and lists every problem with it. */
export function checkProduct(
  raw: unknown,
): { product: ProductInput } | { errors: FieldError[] } {
  if (!isObject(raw)) throw new BadRequest("product must be an object");
  const errors: FieldError[] = [];
  const fail = (field: string, code: FieldError["code"]) => errors.push({ field, code });

  const name = i18n(raw.name);
  if (!name.en) fail("name.en", "required");
  checkLength(name, "name", LIMITS.name, fail);

  const description = i18n(raw.description);
  checkLength(description, "description", LIMITS.description, fail);

  const categoryId = str(raw.category_id);
  if (!categoryId) fail("category_id", "required");
  else if (!UUID_PATTERN.test(categoryId)) fail("category_id", "invalid");

  const brand = str(raw.brand);
  if (brand && brand.length > LIMITS.brand) fail("brand", "too_long");

  const highlights = list(raw.highlights).map(i18n).filter((h) => h.en || h.km);
  if (highlights.length > LIMITS.highlights) fail("highlights", "too_many");
  highlights.forEach((h, i) => {
    if (!h.en) fail(`highlights.${i}.en`, "required");
    checkLength(h, `highlights.${i}`, LIMITS.highlight, fail);
  });

  const specs = list(raw.specs)
    .filter(isObject)
    .map((s) => ({ name: str(s.name) ?? "", value: str(s.value) ?? "" }))
    .filter((s) => s.name || s.value);
  if (specs.length > LIMITS.specs) fail("specs", "too_many");
  specs.forEach((s, i) => {
    if (!s.name) fail(`specs.${i}.name`, "required");
    if (!s.value) fail(`specs.${i}.value`, "required");
    if (s.name.length > LIMITS.specName) fail(`specs.${i}.name`, "too_long");
    if (s.value.length > LIMITS.specValue) fail(`specs.${i}.value`, "too_long");
  });

  const tags = [...new Set(list(raw.tags).map(str).filter((t): t is string => !!t))];
  if (tags.length > LIMITS.tags) fail("tags", "too_many");
  if (tags.some((t) => t.length > LIMITS.tag)) fail("tags", "too_long");

  const options = list(raw.options).filter(isObject).map((o) => ({
    name: i18n(o.name),
    values: [...new Set(list(o.values).map(str).filter((v): v is string => !!v))],
  }));
  if (options.length > LIMITS.options) fail("options", "too_many");
  options.forEach((o, i) => {
    if (!o.name.en) fail(`options.${i}.name`, "required");
    if (o.values.length === 0) fail(`options.${i}.values`, "required");
    if (o.values.length > LIMITS.optionValues) fail(`options.${i}.values`, "too_many");
  });

  const variants = list(raw.variants).filter(isObject).map((v, i) => variant(v, i, fail));
  if (variants.length === 0) fail("variants", "required");
  if (variants.length > LIMITS.variants) fail("variants", "too_many");
  const seen = new Set<string>();
  variants.forEach((v, i) => {
    const key = v.sku.toUpperCase();
    if (v.sku && seen.has(key)) fail(`variants.${i}.sku`, "duplicate");
    seen.add(key);
  });

  const rfqEnabled = raw.rfq_enabled === true;
  const rfqMin = int(raw.rfq_min_qty);
  const rfqMultiple = int(raw.rfq_multiple) ?? 1;
  if (rfqEnabled && rfqMin === undefined) fail("rfq_min_qty", "required");
  if (rfqMin !== undefined && !(rfqMin >= 1 && rfqMin <= LIMITS.maxRfqQty)) {
    fail("rfq_min_qty", "invalid");
  }
  if (!(rfqMultiple >= 1 && rfqMultiple <= LIMITS.maxRfqQty)) fail("rfq_multiple", "invalid");

  const skus = new Set(variants.map((v) => v.sku));
  const images = list(raw.images).filter(isObject).map((img, i) => {
    const path = str(img.path) ?? "";
    const alt = i18n(img.alt);
    const variantSku = str(img.variant_sku);
    if (!path.startsWith("products/") || path.includes("..")) fail(`images.${i}.path`, "invalid");
    if (!alt.en) fail(`images.${i}.alt`, "required");
    checkLength(alt, `images.${i}.alt`, LIMITS.alt, fail);
    if (variantSku && !skus.has(variantSku)) fail(`images.${i}.variant_sku`, "invalid");
    return {
      ...(optionalId(img.id, `images.${i}.id`, fail)),
      path,
      alt,
      ...(variantSku ? { variant_sku: variantSku } : {}),
    };
  });
  if (images.length > LIMITS.images) fail("images", "too_many");

  const status = raw.status === "active" ? "active" : "draft";
  const slug = str(raw.slug);
  if (slug && !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) fail("slug", "invalid");

  if (errors.length > 0) return { errors };
  return {
    product: {
      ...(optionalId(raw.id, "id", fail)),
      category_id: categoryId!,
      ...(slug ? { slug } : {}),
      ...(brand ? { brand } : {}),
      name,
      description,
      highlights,
      specs,
      tags,
      options,
      status,
      is_best_seller: raw.is_best_seller === true,
      same_day: raw.same_day !== false,
      rfq_enabled: rfqEnabled,
      ...(rfqMin !== undefined ? { rfq_min_qty: rfqMin } : {}),
      rfq_multiple: rfqMultiple,
      variants,
      images,
    },
  };
}

function variant(
  v: Record<string, unknown>,
  i: number,
  fail: (field: string, code: FieldError["code"]) => void,
): VariantInput {
  const sku = str(v.sku) ?? "";
  if (!sku) fail(`variants.${i}.sku`, "required");
  else if (!SKU_PATTERN.test(sku)) fail(`variants.${i}.sku`, "invalid");

  const price = int(v.price_cents);
  if (price === undefined) fail(`variants.${i}.price_cents`, "required");
  else if (!(price >= 1 && price <= LIMITS.maxPriceCents)) {
    fail(`variants.${i}.price_cents`, "invalid");
  }

  const compareAt = int(v.compare_at_cents);
  if (compareAt !== undefined && !(price !== undefined && compareAt > price)) {
    fail(`variants.${i}.compare_at_cents`, "invalid");
  }

  const qty = int(v.initial_qty);
  if (qty !== undefined && !(qty >= 0 && qty <= LIMITS.maxQty)) {
    fail(`variants.${i}.initial_qty`, "invalid");
  }

  const barcode = str(v.barcode);
  if (barcode && (barcode.length > LIMITS.barcode || !/^[\x21-\x7e]+$/.test(barcode))) {
    fail(`variants.${i}.barcode`, "invalid");
  }

  const attributes: Record<string, string> = {};
  if (isObject(v.attributes)) {
    for (const [key, value] of Object.entries(v.attributes)) {
      const k = key.trim();
      const val = str(value);
      if (k && val) attributes[k] = val;
    }
  }

  return {
    ...(optionalId(v.id, `variants.${i}.id`, fail)),
    sku,
    ...(barcode ? { barcode } : {}),
    attributes,
    active: v.active !== false,
    price_cents: price ?? 0,
    ...(compareAt !== undefined ? { compare_at_cents: compareAt } : {}),
    ...(qty !== undefined && !v.id ? { initial_qty: qty } : {}),
  };
}

function optionalId(
  value: unknown,
  field: string,
  fail: (field: string, code: FieldError["code"]) => void,
): { id?: string } {
  if (value === undefined || value === null || value === "") return {};
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    fail(field, "invalid");
    return {};
  }
  return { id: value };
}

function checkLength(
  text: I18n,
  field: string,
  max: number,
  fail: (field: string, code: FieldError["code"]) => void,
) {
  if ((text.en?.length ?? 0) > max) fail(`${field}.en`, "too_long");
  if ((text.km?.length ?? 0) > max) fail(`${field}.km`, "too_long");
}

/** {"en": " x ", "km": ""} -> {"en": "x"}. */
export function i18n(value: unknown): I18n {
  if (!isObject(value)) return {};
  const out: I18n = {};
  const en = str(value.en);
  const km = str(value.km);
  if (en) out.en = en;
  if (km) out.km = km;
  return out;
}

function str(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed === "" ? undefined : trimmed;
}

function int(value: unknown): number | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  const n = typeof value === "number" ? value : Number(value);
  return Number.isInteger(n) ? n : NaN;
}

function list(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

export function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
