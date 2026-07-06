// parse-medication — the only backend Dose needs at launch.
//
// Transforms free-text or OCR'd packaging text into a structured medication draft using Claude with
// Structured Outputs. It holds the Anthropic key server-side, stores nothing, manages no users, and
// schedules nothing. The client always treats the result as a DRAFT and routes it through the
// human review gate.
//
// Request  (POST): { inputType: "text" | "scan", inputText?, ocrText?, locale?, timezone? }
// Response (200) : { medicines: DraftMedication[] }   // one entry per detected medication

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
// Cheap, fast, supports Structured Outputs. Bump to "claude-sonnet-4-6" only if real RU/KK
// packaging accuracy demands it (decide empirically, per the build spec).
const MODEL = "claude-haiku-4-5";
const ANTHROPIC_VERSION = "2023-06-01";
const MAX_TOKENS = 2048;

const SYSTEM_PROMPT = `You are a medication data extraction engine. You convert user free-text or OCR'd packaging text into a structured medication record. Input may be in English, Russian, or Kazakh — extract accurately regardless of language, and normalize the medication name to its standard form. Rules: extract only what is present; never invent a name, dosage, form, quantity, or time that isn't supported by the input — use null for anything absent. Never give medical advice, never interpret safety, never suggest dose changes. If a schedule is implied but not explicit ("twice a day"), infer reasonable local times, set scheduleInferred to true, and add "schedule" to uncertainFields. Add any field you are unsure about to uncertainFields. Set confidence to "low" whenever a dosage or the drug name is uncertain.

Return one entry in "medicines" per distinct medication found. Schedule times are 24-hour "HH:mm" strings in the user's local time.`;

// Generic field names only — no PHI in the schema. The medication text lives only in message content.
const SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["medicines"],
  properties: {
    medicines: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "name", "dosage", "form", "frequency", "schedule",
          "quantity", "scheduleInferred", "uncertainFields", "confidence",
        ],
        properties: {
          name: { type: ["string", "null"] },
          dosage: { type: ["string", "null"] },
          form: { type: ["string", "null"] },
          frequency: { type: ["string", "null"] },
          schedule: { type: "array", items: { type: "string" } },
          quantity: { type: ["string", "null"] },
          scheduleInferred: { type: "boolean" },
          uncertainFields: { type: "array", items: { type: "string" } },
          confidence: { type: "string", enum: ["high", "medium", "low"] },
        },
      },
    },
  },
};

// Deliberately NO CORS headers: the only legitimate client is the native app, and URLSession
// ignores CORS entirely. Granting `Access-Control-Allow-Origin: *` would let any web page script
// calls against the endpoint (with the extractable anon key) — one less lever for cost abuse.
// OPTIONS still gets a 200 (the app's reachability probe sends one and reads only the status).

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

// deno-lint-ignore no-explicit-any
function withRequiresReview(m: any) {
  // The function (not the model) owns the gate flag — never trust the model for it.
  const requiresReview =
    m?.confidence !== "high" ||
    (Array.isArray(m?.uncertainFields) && m.uncertainFields.length > 0) ||
    m?.scheduleInferred === true ||
    !m?.name;
  return { ...m, requiresReview };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return json({ error: "server_misconfigured", detail: "ANTHROPIC_API_KEY is not set" }, 500);

  // deno-lint-ignore no-explicit-any
  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const { inputType, inputText, ocrText, locale, timezone } = payload ?? {};
  const text = inputType === "scan" ? ocrText : inputText;
  if ((inputType !== "text" && inputType !== "scan") || typeof text !== "string" || text.trim() === "") {
    return json({
      error: "invalid_request",
      detail: "Provide inputType ('text' | 'scan') and the matching text field (inputText | ocrText).",
    }, 400);
  }

  // Size cap: a single label/description never needs more than a few KB. Uncapped input both blows
  // past model limits on dense package-insert scans (opaque 502s) and is the main cost lever for
  // scripted abuse of the endpoint.
  const MAX_INPUT_CHARS = 20_000;
  if (text.length > MAX_INPUT_CHARS) {
    return json({
      error: "too_long",
      detail: `Input is ${text.length} characters (limit ${MAX_INPUT_CHARS}). Try scanning just the label area with the name and directions.`,
    }, 400);
  }

  const hints: string[] = [];
  if (typeof locale === "string" && locale) hints.push(`User locale: ${locale}.`);
  if (typeof timezone === "string" && timezone) hints.push(`User timezone: ${timezone}.`);
  const framing = inputType === "scan"
    ? "The following is raw OCR text from medication packaging. It may be noisy and may mix English, Russian, and Kazakh."
    : "The following is a free-text description from the user.";
  const userContent = `${framing}${hints.length ? " " + hints.join(" ") : ""}\n\n"""\n${text}\n"""`;

  const anthropicRequest = {
    model: MODEL,
    max_tokens: MAX_TOKENS,
    system: SYSTEM_PROMPT,
    messages: [{ role: "user", content: userContent }],
    // Structured Outputs grammar-constrains the response to valid JSON — no "return only JSON"
    // prompting, no JSON.parse retries. (Do NOT add message prefilling — incompatible with this.)
    output_config: { format: { type: "json_schema", schema: SCHEMA } },
  };

  let resp: Response;
  try {
    resp = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body: JSON.stringify(anthropicRequest),
    });
  } catch (e) {
    return json({ error: "upstream_unreachable", detail: String(e) }, 502);
  }

  if (!resp.ok) {
    return json({ error: "upstream_error", status: resp.status, detail: await resp.text() }, 502);
  }

  const data = await resp.json();

  // Observability only: log token usage so per-parse cost is visible in Supabase function logs.
  // This never touches the response body (the client contract stays byte-for-byte identical) and
  // logs ONLY token counts/model/stop_reason — never the medication text or any PHI.
  const usage = data.usage ?? {};
  console.log(JSON.stringify({
    event: "parse_usage",
    model: data.model ?? null,
    stop_reason: data.stop_reason ?? null,
    input_tokens: usage.input_tokens ?? null,
    output_tokens: usage.output_tokens ?? null,
    cache_read_input_tokens: usage.cache_read_input_tokens ?? null,
    cache_creation_input_tokens: usage.cache_creation_input_tokens ?? null,
  }));

  // Handle stop_reason BEFORE reading content — both of these mean the output may not match schema.
  if (data.stop_reason === "refusal") {
    return json({ error: "refusal", detail: "The request was declined. Try entering the medicine manually." }, 422);
  }
  if (data.stop_reason === "max_tokens") {
    return json({ error: "incomplete", detail: "The response was cut off. Try simpler or shorter input." }, 422);
  }

  // deno-lint-ignore no-explicit-any
  const block = Array.isArray(data.content) ? data.content.find((b: any) => b.type === "text") : null;
  if (!block?.text) return json({ error: "empty_output" }, 502);

  let parsed: { medicines?: unknown };
  try {
    parsed = JSON.parse(block.text);
  } catch {
    return json({ error: "unparseable_output" }, 502);
  }

  const medicines = Array.isArray(parsed.medicines) ? parsed.medicines.map(withRequiresReview) : [];
  return json({ medicines });
});
