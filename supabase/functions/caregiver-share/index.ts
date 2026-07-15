// caregiver-share — the WRITE path (create + revoke) for a caregiver share. Reading is a SEPARATE public
// function (caregiver-share-view); this one is `verify_jwt = true` (see config.toml), so the platform
// requires a valid JWT — the app sends the anon key — and applies rate limiting, matching parse-medication.
// This is the FIRST place Dose data leaves the device, so:
//   - the payload is already minimized on-device and EXCLUDES HealthKit-sourced values,
//   - the token is a 192-bit unguessable bearer credential; the row auto-expires; revoke is a hard delete.
//
// POST   { snapshot: CaregiverShareSnapshot, ttlDays?: 1..30 }  -> { token, viewUrl, expiresAt }
// DELETE { token }  (or ?t=<token>)                             -> { ok: true }  (idempotent revoke)

import { createClient } from "jsr:@supabase/supabase-js@2";

const MAX_BODY_BYTES = 64 * 1024;        // a minimized snapshot is a few KB; cap oversized writes
const DEFAULT_TTL_DAYS = 7;
const MAX_TTL_DAYS = 30;
// The static viewer (GitHub Pages, served from /docs). The share link points here; the page fetches
// the caregiver-share-view function (JSON) by token and renders it client-side.
const VIEWER_BASE = "https://thestartofadri.github.io/dose/caregiver/";

// No CORS: the only legitimate caller is the native app (URLSession ignores CORS); browsers never write.
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

function db() {
  // Service-role client bypasses RLS; the table denies all anon access, so only this function writes it.
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
  if (req.method === "OPTIONS") return new Response("ok");

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

    // Opportunistic purge of already-expired rows — a guaranteed cleanup path that bounds table growth
    // without depending on pg_cron. Best-effort: a failure here never blocks the create.
    await supabase.from("caregiver_shares").delete().lt("expires_at", new Date().toISOString());

    const { error } = await supabase.from("caregiver_shares")
      .insert({ token, payload: snapshot, expires_at: expiresAt });
    if (error) return json({ error: "store_failed" }, 502);   // no DB detail leaked to the client

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
    if (error) return json({ error: "revoke_failed" }, 502);  // no DB detail leaked to the client
    return json({ ok: true });   // idempotent: deleting an already-gone share still succeeds
  }

  return json({ error: "method_not_allowed" }, 405);
});
