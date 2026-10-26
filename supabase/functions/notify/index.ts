// F07 · see _shared/notify_flows.ts (notifyRequest) for the rules.
import { notifyHttpDeps } from "../_shared/notify_deps.ts";
import { notifyRequest } from "../_shared/notify_flows.ts";
import { handler } from "../_shared/http.ts";

Deno.serve(handler(notifyRequest, notifyHttpDeps));
