// F08 · see _shared/staff_flows.ts (manageStaff) for the rules.
import { handler } from "../_shared/http.ts";
import { staffDeps } from "../_shared/staff_deps.ts";
import { manageStaff } from "../_shared/staff_flows.ts";

Deno.serve(handler(manageStaff, staffDeps));
