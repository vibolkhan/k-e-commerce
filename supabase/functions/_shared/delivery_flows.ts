import { BadRequest } from "./errors.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface DeliveryDeps {
  userIdFor(authorization: string | null): Promise<string | null>;
  member(userId: string): Promise<{ staff_role: string; status: string } | null>;
  quote(addressId: string, subtotalCents: number, authorization: string): Promise<unknown>;
  saveZone(actorId: string, body: Record<string, unknown>): Promise<unknown>;
}

export async function quoteDelivery(
  deps: DeliveryDeps,
  body: Record<string, unknown>,
  req: Request,
) {
  const authorization = req.headers.get("authorization");
  if (!await deps.userIdFor(authorization)) return { status: "unauthorized" };
  if (typeof body.address_id !== "string" || !UUID.test(body.address_id)) {
    throw new BadRequest("address_id must be a UUID");
  }
  if (typeof body.subtotal_cents !== "number" || !Number.isInteger(body.subtotal_cents) ||
    body.subtotal_cents < 0 || body.subtotal_cents > 100_000_000) {
    throw new BadRequest("subtotal_cents must be a non-negative integer");
  }
  return await deps.quote(body.address_id, body.subtotal_cents, authorization!);
}

export async function manageDeliveryZone(
  deps: DeliveryDeps,
  body: Record<string, unknown>,
  req: Request,
) {
  const actor = await deps.userIdFor(req.headers.get("authorization"));
  if (!actor) return { status: "unauthorized" };
  const member = await deps.member(actor);
  if (member?.status !== "active" || member.staff_role !== "super_admin") {
    return { status: "forbidden" };
  }
  if (body.action !== "save") throw new BadRequest("action must be save");
  if (typeof body.id !== "string" || !UUID.test(body.id)) throw new BadRequest("id must be a UUID");
  for (const field of ["name", "polygon", "fee_cents", "free_threshold_cents", "same_day", "cod_enabled", "cod_limit_cents", "active"]) {
    if (body[field] == null) throw new BadRequest(`${field} is required`);
  }
  return await deps.saveZone(actor, body);
}

