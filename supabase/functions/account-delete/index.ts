// F06 · see _shared/account_flows.ts (deleteAccount) for the rules.
import { accountDeps } from "../_shared/account_deps.ts";
import { deleteAccount } from "../_shared/account_flows.ts";
import { handler } from "../_shared/http.ts";

Deno.serve(handler(deleteAccount, accountDeps));
