// JSON + CORS plumbing shared by every Edge Function.

import { type AuthDeps, BadRequest, type FlowResult } from "./auth_flows.ts";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

type Flow = (deps: AuthDeps, body: Record<string, unknown>) => Promise<FlowResult>;

/** Wraps a flow as a request handler: CORS, JSON body, 400/500 mapping. */
export function handler(flow: Flow, deps: () => AuthDeps) {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return json({ error: "bad_request", message: "body must be JSON" }, 400);
    }
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      return json({ error: "bad_request", message: "body must be an object" }, 400);
    }

    try {
      return json(await flow(deps(), body as Record<string, unknown>));
    } catch (e) {
      if (e instanceof BadRequest) return json({ error: "bad_request", message: e.message }, 400);
      console.error(e);
      return json({ error: "server_error" }, 500);
    }
  };
}
