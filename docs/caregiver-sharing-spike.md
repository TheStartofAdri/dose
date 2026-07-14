# Caregiver Sharing — Spike / Design Doc

**Status:** exploratory spike. Phase 0 (this doc + a pure, offline data-shaping prototype) is
implemented. Phase 1+ (anything that puts data on a server) is **NOT** built — it reopens the locked
"local-only" decision and needs an explicit go-ahead. This doc scopes the options and the decisions.

## 1. What "caregiver sharing" means (scoped)
A patient shares a **read-only** view of their care data with a trusted caregiver (family member,
nurse). The caregiver sees, and cannot edit:
- adherence summary + today's status,
- upcoming appointments,
- recent symptom/vital trends.

Consent-based, **revocable at any time**, data-minimized. **v1 scope is one-way (patient → caregiver),
read-only.** Two-way (caregiver logs / nudges) is a later phase.

## 2. The crux: health data leaves the device
This is what reopens the locked **local-only** decision. Consequences:
- **Privacy.** Medications, adherence, and symptoms are sensitive health data. Sharing them off-device
  requires explicit informed consent, encryption in transit + at rest, minimization, retention limits,
  and clean deletion/revocation.
- **HealthKit constraint (hard).** Apple's HealthKit terms restrict sharing HealthKit-derived data with
  third parties / storing it off-device. **Metrics with `source == .healthKit` must be EXCLUDED from any
  server share.** (The prototype below enforces this.)
- **Legal.** Privacy-policy update; GDPR consent basis + right-to-erasure for EU users.

## 3. Architecture options
### Option A — Signed read-only snapshot link (lightest) ✅ recommended for v1
Patient taps "Share": the app builds a minimized `CaregiverShareSnapshot`, uploads it under a random
unguessable token, and gets a link. The caregiver opens the link (web viewer) to a read-only dashboard.
The app re-uploads on foreground (like the notification reschedule) so it stays near-current.
- **Pros:** simplest; **no caregiver account** (preserves Dose's anonymous, hard-paywall model); reuses
  the existing snapshot/report infra + the existing Supabase project; revoke = delete the token; smallest
  reopening of local-only (data leaves only for an explicit, minimized, revocable share).
- **Cons:** not truly live; the link is a bearer credential → mitigate with expiry + revocation + optional PIN.

### Option B — Account-based live sync (heaviest)
Both parties have accounts; a backend DB with row-level security syncs live.
- **Pros:** live, multi-caregiver, foundation for two-way.
- **Cons:** full auth + accounts (breaks the no-accounts simplicity and the anonymous entry paywall),
  real-time sync, much larger security/privacy surface. Over-scoped now.

### Option C — Apple-native (CloudKit sharing, no custom backend)
Share a CloudKit record set (`CKShare`) so a caregiver who also runs the app sees shared data.
- **Pros:** no custom backend; Apple handles identity/auth/encryption; best privacy fit.
- **Cons:** both parties need iOS + iCloud + the app; **Dose uses `@Attribute(.unique)` pervasively, which
  the CloudKit-backed store forbids** → a real model migration; HealthKit-share restriction still applies.
  A strong *future* direction if caregivers are all iOS users, but a big lift.

## 4. Recommendation
- **v1 → Option A.** Best risk-adjusted path: reuses infra, no accounts, trivial revocation, smallest
  reopening of local-only.
- **Option C** is the most privacy-aligned but blocked today by the pervasive unique-constraint usage +
  HealthKit rules; revisit later.
- **Option B** is over-scoped.

## 5. The share payload (Option A) — the safe local prototype (built now)
`CaregiverShareSnapshot` (pure, `Codable`, minimized), built by `CaregiverShareBuilder` by reusing the
tested `ReportBuilder` for adherence + upcoming appointments, and **excluding HealthKit-sourced metrics**:
- `generatedAt`, `patientLabel?` (a user-set nickname, not a real name), `rangeDays`
- `overallAdherencePercent`, per-med `{name, adherence%, taken, missed}`
- `upcomingAppointments {title, subtitle, when}`
- `metrics {name, unit, latest}` — **manual entries only**

This is 100% offline: it proves *what* would be shared without sending anything anywhere. See
`CaregiverShareBuilder` + `CaregiverShareTests` (HealthKit exclusion + Codable round-trip are tested).

## 6. Phased plan
- **Phase 0 (this spike):** design doc + pure `CaregiverShareSnapshot`/builder + tests. **No network.** ← done.
- **Phase 1 (needs your go-ahead — reopens local-only):** Supabase endpoint to store a snapshot under a
  random token with expiry; a minimal web viewer; in-app "Share with a caregiver" flow (generate/revoke)
  behind the premium gate; a consent screen + privacy-policy update; HealthKit data excluded.
- **Phase 2:** refresh-on-foreground, optional PIN, multiple caregivers, expiry controls.
- **Phase 3 (maybe):** two-way (acknowledge/nudge), or the CloudKit-native path.

## 7. Decisions I need from you (before Phase 1)
1. **Reopen local-only** for a minimized, explicit, revocable share? (Y/N)
2. **Backend:** extend the existing Supabase project (Option A), or pursue CloudKit-native (Option C)?
3. **Privacy:** exclude HealthKit-sourced metrics from any share? (recommended / likely required)
4. **Monetization:** caregiver sharing as a premium feature? (fits the paywall)

## 8. Risks
- HealthKit sharing restrictions → must exclude HK-sourced values (prototype enforces this).
- A share link is a bearer token → expiry + revoke + optional PIN.
- Privacy-policy / legal review required before any server share ships.
- The Supabase project has been prone to pausing (INACTIVE) — a shared-link backend needs reliability.

## 9. Phase 1 status (Option A — signed read-only link)
**Built (not yet deployed / not yet live):**
- Backend: `supabase/functions/caregiver-share` (POST create / GET read-only HTML view / DELETE revoke),
  `caregiver_shares` table with RLS deny-all + optional pg_cron purge, `verify_jwt = false` (token-gated).
- App: `CaregiverShareClient` (create/revoke, tested via a stub transport), `CaregiverShareStore` (the one
  active share, expiry-aware), and the **premium-gated, consent-first `CaregiverShareView`** in Settings.
- The share payload is built from live data with **HealthKit-sourced values excluded** (Phase 0 builder).

**To ship Phase 1 (your steps):**
1. **Deploy** — `supabase db push` (creates the table) + `supabase functions deploy caregiver-share`,
   with the project ACTIVE. (I can run these on your go-ahead, as with the parser deploy.)
2. **Privacy policy** — update it to disclose the optional caregiver share: what's shared, that it's
   stored on the server behind a private link, retention (auto-expire ≤ 7 days), and revocation. This is a
   legal doc — please review/author the final wording.
3. **Configure** — the app already reads `SupabaseURL`/`SupabaseAnonKey`; once deployed, the Settings row
   lights up automatically (until then it shows an "isn't available in this build yet" state).
4. **Device-verify** the create → open-link → revoke round-trip.

**Deliberately still deferred:** optional PIN on the link, multiple caregivers, refresh-on-foreground,
two-way (acknowledge/nudge), and the CloudKit-native path (§3 Option C).
