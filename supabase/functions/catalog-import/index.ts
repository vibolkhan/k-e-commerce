// F09 · see _shared/import_flows.ts (importCatalog) for the rules.
import { handler } from "../_shared/http.ts";
import { catalogDeps } from "../_shared/catalog_deps.ts";
import { importCatalog } from "../_shared/import_flows.ts";

Deno.serve(handler(importCatalog, catalogDeps));
