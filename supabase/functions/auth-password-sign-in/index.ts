// F05 · see _shared/auth_flows.ts (passwordSignIn) for the rules.
import { passwordSignIn } from "../_shared/auth_flows.ts";
import { handler } from "../_shared/http.ts";
import { supabaseDeps } from "../_shared/supabase_deps.ts";

Deno.serve(handler(passwordSignIn, supabaseDeps));
