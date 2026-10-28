// F10 · see _shared/stock_flows.ts (manageInventory) for the rules.
import { handler } from "../_shared/http.ts";
import { stockDeps } from "../_shared/stock_deps.ts";
import { manageInventory } from "../_shared/stock_flows.ts";

Deno.serve(handler(manageInventory, stockDeps));
