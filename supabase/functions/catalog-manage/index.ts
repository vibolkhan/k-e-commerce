// F09 · see _shared/catalog_flows.ts (manageCatalog) for the rules.
import { handler } from "../_shared/http.ts";
import { catalogDeps } from "../_shared/catalog_deps.ts";
import { manageCatalog } from "../_shared/catalog_flows.ts";

Deno.serve(handler(manageCatalog, catalogDeps));
