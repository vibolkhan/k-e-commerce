// JSON + CORS plumbing shared by every Edge Function.

import { BadRequest, Unauthorized } from "./errors.ts";

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

type Flow<D> = (deps: D, body: Record<string, unknown>, req: Request) => Promise<unknown>;

/** Wraps a flow as a request handler: CORS, JSON body, 400/401/500 mapping. */
export function handler<D>(flow: Flow<D>, deps: () => D) {
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
      return json(await flow(deps(), body as Record<string, unknown>, req));
    } catch (e) {
      if (e instanceof BadRequest) return json({ error: "bad_request", message: e.message }, 400);
      if (e instanceof Unauthorized) return json({ error: "unauthorized" }, 401);
      console.error(e);
      return json({ error: "server_error" }, 500);
    }
  };
}
