import { handler } from "../_shared/http.ts";
import { deliveryDeps } from "../_shared/delivery_deps.ts";
import { quoteDelivery } from "../_shared/delivery_flows.ts";

Deno.serve(handler(quoteDelivery, deliveryDeps));

