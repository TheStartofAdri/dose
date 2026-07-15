// caregiver-share-view — the PUBLIC READ path for a caregiver share. Split out from the write/revoke
// function so it alone is `verify_jwt = false` (a caregiver's browser opens the link with no auth
// header); creating/revoking lives in the JWT-gated `caregiver-share` function. Returns the minimized
// snapshot as JSON with permissive CORS — the payload is already minimized on-device + EXCLUDES
// HealthKit values, and access is gated by the unguessable token, so `*` doesn't weaken it. The static
// GitHub Pages viewer fetches this by token and renders it client-side.
//
// GET ?t=<token> -> { snapshot, expiresAt } | 400 missing_token | 404 not_found | 410 expired

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
};

function json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...extra } });
}

function db() {
  // Service-role client bypasses RLS; the table denies all anon access, so only this function reads it.
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return null;
  return createClient(url, key);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "GET") return json({ error: "method_not_allowed" }, 405, CORS);

  const supabase = db();
  if (!supabase) return json({ error: "server_misconfigured" }, 500, CORS);

  const token = new URL(req.url).searchParams.get("t") ?? "";
  if (!token) return json({ error: "missing_token" }, 400, CORS);

  const { data, error } = await supabase.from("caregiver_shares")
    .select("payload, expires_at").eq("token", token).maybeSingle();
  if (error) return json({ error: "lookup_failed" }, 502, CORS);       // no DB detail leaked
  if (!data) return json({ error: "not_found" }, 404, CORS);
  if (new Date(data.expires_at).getTime() < Date.now()) return json({ error: "expired" }, 410, CORS);
  return json({ snapshot: data.payload, expiresAt: data.expires_at }, 200, CORS);
});
