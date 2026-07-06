# Dose backend — `parse-medication`

The only backend Dose needs. A single Supabase edge function that turns text/OCR into a structured
medication draft via Claude (Structured Outputs). It stores nothing and manages no users.

## Deploy (one time)

You need a Supabase project and an Anthropic API key (ideally on a key isolated from other projects).

```bash
supabase login
supabase link --project-ref <YOUR_PROJECT_REF>

# Server-side secret — never shipped in the app:
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...

supabase functions deploy parse-medication
```

Then put your project's public values into `Config/Secrets.xcconfig` (Supabase dashboard →
Project Settings → API):

```
SUPABASE_URL = https://xfyonvkcppjzcyqgjoau.supabase.co
SUPABASE_ANON_KEY = <eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhmeW9udmtjcHBqemN5cWdqb2F1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE2MDM0MjcsImV4cCI6MjA5NzE3OTQyN30.sGZX-ypvbAtBD4NMCcmrvaz-dOqssWWNdTV1mtBoogo>
```

The anon key is safe in the client. The Anthropic key stays only in Supabase secrets.

## Contract

Request (`POST /functions/v1/parse-medication`):

```json
{ "inputType": "text" | "scan",
  "inputText": "<free text>",     // when inputType == "text"
  "ocrText":   "<raw OCR text>",  // when inputType == "scan"
  "locale":    "ru-RU",           // optional
  "timezone":  "Asia/Almaty" }    // optional
```

Response: `{ "medicines": DraftMedication[] }`. The function computes `requiresReview` per medicine.
`stop_reason: "refusal"` → HTTP 422 `{error:"refusal"}`; `"max_tokens"` → 422 `{error:"incomplete"}`.

## Smoke test

By default the function requires a valid JWT; the anon key is one. The app sends both
`Authorization: Bearer <anon>` and `apikey: <anon>`.

```bash
curl -s -X POST "$SUPABASE_URL/functions/v1/parse-medication" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"inputType":"text","inputText":"Парацетамол 500 мг по 1 таблетке 2 раза в день","timezone":"Asia/Almaty"}' | jq
```

Expect `medicines[0].name` normalized, `scheduleInferred: true`, `"schedule"` in `uncertainFields`,
`requiresReview: true`.

> Local run (optional): `supabase functions serve parse-medication --env-file ./supabase/.env.local`
> with `ANTHROPIC_API_KEY=...` in that env file. Do not commit it.
