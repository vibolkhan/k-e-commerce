import { handler } from "../_shared/http.ts";
import { deliveryDeps } from "../_shared/delivery_deps.ts";
import { manageDeliveryZone } from "../_shared/delivery_flows.ts";

Deno.serve(handler(manageDeliveryZone, deliveryDeps));

