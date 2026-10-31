import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { manageDeliveryZone, quoteDelivery, type DeliveryDeps } from "./delivery_flows.ts";

function deps(role = "super_admin"): DeliveryDeps {
  return {
    userIdFor: async (auth) => auth ? "actor" : null,
    member: async () => ({ staff_role: role, status: "active" }),
    quote: async (id, subtotal) => ({ status: "available", address_id: id, subtotal }),
    saveZone: async (_actor, body) => ({ status: "saved", id: body.id }),
  };
}
const req = new Request("http://test", { headers: { authorization: "Bearer token" } });

Deno.test("quote delivery validates and delegates cents", async () => {
  const result = await quoteDelivery(deps(), {
    address_id: "10000000-0000-4000-8000-000000000001", subtotal_cents: 5000,
  }, req);
  assertEquals(result, {
    status: "available", address_id: "10000000-0000-4000-8000-000000000001", subtotal: 5000,
  });
});

Deno.test("quote delivery rejects invalid money", async () => {
  await assertRejects(() => quoteDelivery(deps(), {
    address_id: "10000000-0000-4000-8000-000000000001", subtotal_cents: 1.5,
  }, req));
});

Deno.test("only a super admin saves a zone", async () => {
  const result = await manageDeliveryZone(deps("sales"), { action: "save" }, req);
  assertEquals(result, { status: "forbidden" });
});
