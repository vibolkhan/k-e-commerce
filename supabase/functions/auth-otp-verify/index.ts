// F05 · see _shared/auth_flows.ts (verifyOtp) for the rules.
import { verifyOtp } from "../_shared/auth_flows.ts";
import { handler } from "../_shared/http.ts";
import { supabaseDeps } from "../_shared/supabase_deps.ts";

Deno.serve(handler(verifyOtp, supabaseDeps));
