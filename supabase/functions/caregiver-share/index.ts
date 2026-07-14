// caregiver-share — stores a minimized, read-only caregiver snapshot under an unguessable token and
// serves it as JSON to the external static viewer (GitHub Pages). Part of the caregiver-sharing feature
// (see docs/caregiver-sharing-spike.md). This is the FIRST place Dose data leaves the device, so:
//   - only the patient's app writes (POST) or revokes (DELETE); the token is the bearer credential,
//   - the payload is already minimized on-device and EXCLUDES HealthKit-sourced values,
//   - shares auto-expire, and revoke is a hard delete.
//
// POST   { snapshot: CaregiverShareSnapshot, ttlDays?: 1..30 }  -> { token, viewUrl, expiresAt }
// GET    ?t=<token>                                             -> { snapshot, expiresAt } | 404 | 410
// DELETE { token }  (or ?t=<token>)                             -> { ok: true }  (idempotent revoke)
//
// The GET returns JSON with permissive CORS: Supabase force-serves every *.supabase.co response as
// text/plain under a sandbox CSP (anti-phishing), so the renderable caregiver page CANNOT live here or
// in Supabase Storage — it's hosted on GitHub Pages (VIEWER_BASE) and fetches this JSON by token.
// The data is already minimized and gated by the unguessable token, so `*` here doesn't weaken it.
//
// Deploy PUBLIC (verify_jwt = false, see config.toml): the token — not a JWT — gates access.

import { createClient } from "jsr:@supabase/supabase-js@2";

const MAX_BODY_BYTES = 64 * 1024;        // a minimized snapshot is a few KB; cap abuse/oversized writes
const DEFAULT_TTL_DAYS = 7;
const MAX_TTL_DAYS = 30;
// The static viewer (GitHub Pages, served from /docs). The share link points here; the page fetches
// this function's GET (JSON) by token and renders it client-side.
const VIEWER_BASE = "https://thestartofadri.github.io/dose/caregiver/";

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
};

function json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...extra } });
}

function db() {
  // The service-role client bypasses RLS; the table denies all anon access, so only this function reads/writes.
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return null;
  return createClient(url, key);
}

function randomToken(): string {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  // URL-safe base64 (no padding) — ~32 chars, 192 bits of entropy.
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const supabase = db();
  if (!supabase) return json({ error: "server_misconfigured" }, 500);
  const url = new URL(req.url);

  // ---- Create ----------------------------------------------------------------
  if (req.method === "POST") {
    const raw = await req.arrayBuffer();
    if (raw.byteLength > MAX_BODY_BYTES) return json({ error: "too_large" }, 400);
    // deno-lint-ignore no-explicit-any
    let payload: any;
    try { payload = JSON.parse(new TextDecoder().decode(raw)); } catch { return json({ error: "invalid_json" }, 400); }

    const snapshot = payload?.snapshot;
    if (!snapshot || typeof snapshot !== "object" || !Array.isArray(snapshot.medicines)) {
      return json({ error: "invalid_request", detail: "Provide a { snapshot } object." }, 400);
    }
    const ttlDays = Math.min(MAX_TTL_DAYS, Math.max(1, Number(payload?.ttlDays) || DEFAULT_TTL_DAYS));
    const token = randomToken();
    const expiresAt = new Date(Date.now() + ttlDays * 86_400_000).toISOString();

    const { error } = await supabase.from("caregiver_shares")
      .insert({ token, payload: snapshot, expires_at: expiresAt });
    if (error) return json({ error: "store_failed", detail: error.message }, 502);

    return json({ token, viewUrl: `${VIEWER_BASE}?t=${token}`, expiresAt });
  }

  // ---- Revoke ----------------------------------------------------------------
  if (req.method === "DELETE") {
    let token = url.searchParams.get("t") ?? "";
    if (!token) {
      try { token = (await req.json())?.token ?? ""; } catch { /* body optional */ }
    }
    if (!token) return json({ error: "invalid_request", detail: "Provide a token." }, 400);
    const { error } = await supabase.from("caregiver_shares").delete().eq("token", token);
    if (error) return json({ error: "revoke_failed", detail: error.message }, 502);
    return json({ ok: true });   // idempotent: deleting an already-gone share still succeeds
  }

  // ---- Read (for the external viewer) ----------------------------------------
  if (req.method === "GET") {
    const token = url.searchParams.get("t") ?? "";
    if (!token) return json({ error: "missing_token" }, 400, CORS);

    const { data, error } = await supabase.from("caregiver_shares")
      .select("payload, expires_at").eq("token", token).maybeSingle();
    if (error) return json({ error: "lookup_failed" }, 502, CORS);
    if (!data) return json({ error: "not_found" }, 404, CORS);
    if (new Date(data.expires_at).getTime() < Date.now()) return json({ error: "expired" }, 410, CORS);
    return json({ snapshot: data.payload, expiresAt: data.expires_at }, 200, CORS);
  }

  return json({ error: "method_not_allowed" }, 405);
});
