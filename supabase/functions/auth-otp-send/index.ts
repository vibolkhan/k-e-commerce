// F05 · see _shared/auth_flows.ts (sendOtp) for the rules.
import { sendOtp } from "../_shared/auth_flows.ts";
import { handler } from "../_shared/http.ts";
import { supabaseDeps } from "../_shared/supabase_deps.ts";

Deno.serve(handler(sendOtp, supabaseDeps));
