// caregiver-share — stores a minimized, read-only caregiver snapshot under an unguessable token and
// serves a read-only web view of it. Part of the caregiver-sharing feature (see
// docs/caregiver-sharing-spike.md). This is the FIRST place Dose data leaves the device, so:
//   - only the patient's app writes (POST) or revokes (DELETE); the token is the bearer credential,
//   - the payload is already minimized on-device and EXCLUDES HealthKit-sourced values,
//   - shares auto-expire, and revoke is a hard delete.
//
// POST   { snapshot: CaregiverShareSnapshot, ttlDays?: 1..30 }  -> { token, viewUrl, expiresAt }
// GET    ?t=<token>                                             -> text/html read-only view (or 404/410)
// DELETE { token }  (or ?t=<token>)                             -> { ok: true }  (idempotent revoke)
//
// Deploy PUBLIC (verify_jwt = false, see config.toml): the web view is a top-level browser navigation
// that can't send an auth header, so the random token — not a JWT — gates access.

import { createClient } from "jsr:@supabase/supabase-js@2";

const MAX_BODY_BYTES = 64 * 1024;        // a minimized snapshot is a few KB; cap abuse/oversized writes
const DEFAULT_TTL_DAYS = 7;
const MAX_TTL_DAYS = 30;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}
function html(body: string, status = 200): Response {
  return new Response(body, { status, headers: { "content-type": "text/html; charset=utf-8" } });
}

// HTML-escape every interpolated string — med names, titles, and the patient label are user-controlled.
function esc(v: unknown): string {
  return String(v ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
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

    const { error } = await supabase.from("caregiver_shares")
      .insert({ token, payload: snapshot, expires_at: expiresAt });
    if (error) return json({ error: "store_failed", detail: error.message }, 502);

    const viewUrl = `${url.origin}${url.pathname}?t=${token}`;
    return json({ token, viewUrl, expiresAt });
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

  // ---- View (browser navigation) --------------------------------------------
  if (req.method === "GET") {
    const token = url.searchParams.get("t") ?? "";
    if (!token) return html(page("Nothing to show", "<p>This link is missing its share code.</p>"), 400);

    const { data, error } = await supabase.from("caregiver_shares")
      .select("payload, expires_at").eq("token", token).maybeSingle();
    if (error) return html(page("Something went wrong", "<p>Please try again later.</p>"), 502);
    if (!data) return html(page("Share not found", "<p>This share was revoked or never existed.</p>"), 404);
    if (new Date(data.expires_at).getTime() < Date.now()) {
      return html(page("Share expired", "<p>Ask the patient to share an updated link.</p>"), 410);
    }
    return html(renderSnapshot(data.payload));
  }

  return json({ error: "method_not_allowed" }, 405);
});

// ---- HTML view ---------------------------------------------------------------

function page(title: string, inner: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>${esc(title)} · Dose</title>
<style>
:root{color-scheme:light dark}
body{font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;margin:0;background:#f2f2f7;color:#1c1c1e}
@media(prefers-color-scheme:dark){body{background:#000;color:#f2f2f7}.card{background:#1c1c1e!important}}
.wrap{max-width:640px;margin:0 auto;padding:24px 16px 48px}
h1{font-size:22px;margin:0 0 4px}.sub{color:#8e8e93;font-size:13px;margin:0 0 20px}
.card{background:#fff;border-radius:14px;padding:16px;margin:0 0 14px}
.card h2{font-size:13px;text-transform:uppercase;letter-spacing:.4px;color:#8e8e93;margin:0 0 10px}
.row{display:flex;justify-content:space-between;gap:12px;padding:6px 0;border-top:1px solid rgba(128,128,128,.15)}
.row:first-of-type{border-top:0}.row .v{color:#8e8e93;text-align:right}
.big{font-size:34px;font-weight:700;margin:2px 0}
.foot{color:#8e8e93;font-size:12px;margin-top:24px;text-align:center}
</style></head><body><div class="wrap">${inner}</div></body></html>`;
}

// deno-lint-ignore no-explicit-any
function renderSnapshot(s: any): string {
  const dt = (iso: string) => {
    try { return new Date(iso).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" }); }
    catch { return esc(iso); }
  };
  const who = s?.patientLabel ? esc(s.patientLabel) : "A patient";
  const parts: string[] = [];

  const overall = s?.overallAdherencePercent;
  parts.push(`<div class="card"><h2>Adherence · last ${esc(s?.rangeDays ?? 30)} days</h2>
    <div class="big">${overall == null ? "—" : esc(overall) + "%"}</div>
    <div class="sub">overall doses taken on time</div>
    ${(s?.medicines ?? []).map((m: any) =>
      `<div class="row"><span>${esc(m?.name)}</span><span class="v">${m?.adherencePercent == null ? "—" : esc(m.adherencePercent) + "%"} · ${esc(m?.taken ?? 0)} taken / ${esc(m?.missed ?? 0)} missed</span></div>`).join("")}
  </div>`);

  if (Array.isArray(s?.upcomingAppointments) && s.upcomingAppointments.length) {
    parts.push(`<div class="card"><h2>Upcoming appointments</h2>
      ${s.upcomingAppointments.map((a: any) =>
        `<div class="row"><span>${esc(a?.title)}${a?.subtitle ? " · " + esc(a.subtitle) : ""}</span><span class="v">${dt(a?.when)}</span></div>`).join("")}
    </div>`);
  }

  if (Array.isArray(s?.metrics) && s.metrics.length) {
    parts.push(`<div class="card"><h2>Recent symptoms &amp; vitals</h2>
      ${s.metrics.map((m: any) =>
        `<div class="row"><span>${esc(m?.name)}</span><span class="v">${m?.latest == null ? "—" : esc(m.latest)}${m?.unit ? " " + esc(m.unit) : ""}</span></div>`).join("")}
    </div>`);
  }

  const inner = `<h1>${who}'s care summary</h1>
    <p class="sub">Read-only, shared from Dose${s?.generatedAt ? " · updated " + dt(s.generatedAt) : ""}</p>
    ${parts.join("")}
    <p class="foot">A read-only summary shared by the patient. Not a medical record, and not medical advice.</p>`;
  return page("Care summary", inner);
}
