// ============================================================================
// JABRAN & CO. — shared LLM client for the edge functions (Deno).
//
// Used by advisory-agent, ai-accountant and analytics-agent. Mirrors the way
// the owner's other product (ScholexAI, src/lib/ai/llm-core.ts) talks to
// Claude, so both products behave the same:
//
// PROVIDER (selectProvider):
//   • AI_PROVIDER = "anthropic" | "gemini" wins when set (no key for the
//     chosen one → no provider).
//   • Otherwise Claude when ANTHROPIC_API_KEY is set, else Gemini when
//     GEMINI_API_KEY is set, else none (callers answer "not configured").
//   NOTE: AI_PROVIDER is also read by the retired ai-agent function.
//
// CLAUDE (official SDK, npm:@anthropic-ai/sdk@1.3.0):
//   • model  ANTHROPIC_MODEL  (default claude-haiku-5-5 — ScholexAI's helper tier)
//   • effort ANTHROPIC_EFFORT (low | medium | high | xhigh | max; default low)
//   • adaptive thinking, output_config.effort, NO temperature; max_tokens =
//     the caller's reply size + room for thinking (low 4096, medium 8192,
//     high 16384, xhigh/max 32768).
//   • system prompt as one text block, cached (cache_control ephemeral) when
//     the caller sets `cache`.
//   • JSON requests: Claude has no schema-less JSON mode, so the system prompt
//     gets JSON_ONLY appended and the reply is read with extractJson.
//   • only `text` blocks are read; stop_reason "refusal" → reason "blocked".
//   • Opus (claude-opus-*) and claude-sonnet-5-5 go through the beta namespace
//     with the server-side refusal fallback (fallbacks: "default"); Haiku has
//     no fallback.
//
// GEMINI (fallback): exactly the request the functions sent before this
//   module existed — POST generativelanguage.googleapis.com/v1beta/openai/
//   chat/completions, Bearer GEMINI_API_KEY, model gemini-3.1-flash-lite,
//   { model, temperature, max_tokens, response_format?, messages:[system,…] }.
//
// BOTH: one retry on 429 / 503 / 529 after the provider's Retry-After
//   (clamped to 1.5–8 s). Never throws. Logs provider, model, status and token
//   counts only — never keys, prompts or user text.
// ============================================================================

import Anthropic from "npm:@anthropic-ai/sdk@1.3.0";

export type ChatMsg = { role: "user" | "assistant"; content: string };

export type LlmRequest = {
  system: string;
  messages: ChatMsg[];
  /** The reply's size in tokens (Claude also gets room for thinking above it). */
  maxTokens: number;
  json?: boolean;
  /** Gemini only: Claude's newer models refuse a temperature, so it is never sent to Claude. */
  temperature?: number;
  /** The system prompt is long and the same for many calls: Claude caches it. */
  cache?: boolean;
  /** One attempt's timeout (default 60 s). */
  timeoutMs?: number;
};

export type LlmResult =
  | { ok: true; text: string; json: unknown | null; provider: "anthropic" | "gemini"; model: string; usage: { input: number; output: number } }
  | { ok: false; reason: "no-provider" | "http" | "timeout" | "blocked" | "empty"; status?: number; detail?: string /* short, no secrets */ };

export type ClaudeEffort = "low" | "medium" | "high" | "xhigh" | "max";

export type ProviderConfig =
  | { provider: "anthropic"; apiKey: string; model: string; effort: ClaudeEffort }
  | { provider: "gemini"; apiKey: string; model: string };

/** Test seams: the env map, `fetch` (the SDK's too) and the retry wait. */
export type CallDeps = {
  env?: Record<string, string | undefined>;
  fetch?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
};

const ANTHROPIC_URL = "https://api.anthropic.com";
const ANTHROPIC_DEFAULT_MODEL = "claude-haiku-5-5";
const ANTHROPIC_DEFAULT_EFFORT: ClaudeEffort = "low";
const EFFORTS: readonly ClaudeEffort[] = ["low", "medium", "high", "xhigh", "max"];
// Thinking counts toward max_tokens, so Claude gets this much room for it above the caller's reply size.
const THINKING_ROOM: Record<ClaudeEffort, number> = { low: 4_096, medium: 8_192, high: 16_384, xhigh: 32_768, max: 32_768 };
// Opus's (and Sonnet 5.5's) server-side refusal fallback ("default": Anthropic's choice of model).
const FALLBACK_BETA = "server-side-fallback-2026-07-01";
// Claude has no JSON reply mode without a schema: a JSON request says so in its system prompt (read with extractJson).
const JSON_ONLY = "Answer with the JSON value alone: no words before or after it, and no code fences.";

const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions";
// What all three functions hard-coded before this module (none read GEMINI_MODEL).
const GEMINI_MODEL = "gemini-3.1-flash-lite";

const DEFAULT_TIMEOUT_MS = 60_000;
// 529: Claude is overloaded, retried as a 503 is.
const RETRYABLE_STATUS = new Set([429, 503, 529]);
const RETRY_MIN_MS = 1500;
const RETRY_MAX_MS = 8000;
const DETAIL_MAX = 300;

/** ANTHROPIC_EFFORT when it names one of Claude's five levels, else the default. */
function effortOf(raw: string | undefined): ClaudeEffort {
  const named = (raw || "").trim().toLowerCase();
  return EFFORTS.find((e) => e === named) ?? ANTHROPIC_DEFAULT_EFFORT;
}

function anthropicFromEnv(env: Record<string, string | undefined>): ProviderConfig | null {
  const apiKey = (env.ANTHROPIC_API_KEY || "").trim();
  if (!apiKey) return null;
  const model = (env.ANTHROPIC_MODEL || "").trim() || ANTHROPIC_DEFAULT_MODEL;
  return { provider: "anthropic", apiKey, model, effort: effortOf(env.ANTHROPIC_EFFORT) };
}

function geminiFromEnv(env: Record<string, string | undefined>): ProviderConfig | null {
  const apiKey = env.GEMINI_API_KEY;
  if (!apiKey) return null;
  return { provider: "gemini", apiKey, model: GEMINI_MODEL };
}

/** AI_PROVIDER ("anthropic" | "gemini") wins when set; otherwise Claude when ANTHROPIC_API_KEY is set, else Gemini when
 *  GEMINI_API_KEY is set, else null (no provider configured). */
export function selectProvider(env: Record<string, string | undefined> = Deno.env.toObject()): ProviderConfig | null {
  const explicit = (env.AI_PROVIDER || "").trim().toLowerCase();
  if (explicit === "anthropic") return anthropicFromEnv(env);
  if (explicit === "gemini") return geminiFromEnv(env);
  return anthropicFromEnv(env) ?? geminiFromEnv(env);
}

/** Strips ``` fences and leading/trailing prose around a JSON value, then
 *  `JSON.parse`s it; returns null when nothing in the text parses as JSON.
 *  (Copied from ScholexAI llm-core.ts.) */
export function extractJson(text: string): unknown | null {
  if (typeof text !== "string") return null;
  let t = text.trim();
  if (!t) return null;
  const fence = t.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  if (fence) t = fence[1].trim();

  const tryParse = (s: string): { value: unknown } | null => {
    try {
      return { value: JSON.parse(s) };
    } catch {
      return null;
    }
  };

  const whole = tryParse(t);
  if (whole) return whole.value;

  // Every plausible JSON start position, in order. A leading citation like
  // "See [1] for details: {...}" must not let the stray "[1]" win over the
  // real object later in the text, so each candidate start is tried in turn
  // rather than only the first one found.
  const starts: number[] = [];
  for (let i = 0; i < t.length; i++) if (t[i] === "{" || t[i] === "[") starts.push(i);

  for (const from of starts) {
    const sub = t.slice(from);
    const fromStart = tryParse(sub);
    if (fromStart) return fromStart.value;

    const ends = [sub.lastIndexOf("}"), sub.lastIndexOf("]")].filter((i) => i !== -1);
    if (!ends.length) continue;
    const to = Math.max(...ends);
    const trimmed = tryParse(sub.slice(0, to + 1));
    if (trimmed) return trimmed.value;
  }
  return null;
}

type Attempt =
  | { kind: "ok"; text: string; usage: { input: number; output: number } }
  | { kind: "retryable"; status: number; retryAfterMs?: number; detail?: string }
  | { kind: "http"; status?: number; detail?: string }
  | { kind: "timeout" }
  | { kind: "empty" }
  | { kind: "blocked" };

/** A Retry-After header given in seconds, as ms; undefined when absent or unreadable (an HTTP-date form is ignored). */
function retryAfterMs(headers: Pick<Headers, "get"> | undefined): number | undefined {
  const raw = headers?.get?.("retry-after");
  const seconds = raw == null || raw.trim() === "" ? NaN : Number(raw);
  return Number.isFinite(seconds) && seconds >= 0 ? seconds * 1000 : undefined;
}

/** A provider's error text, short and with the key masked (it is never in one, but this is the last line of defence). */
function shortDetail(text: string, apiKey: string): string {
  const t = String(text ?? "");
  return (apiKey ? t.split(apiKey).join("[redacted]") : t).slice(0, DETAIL_MAX);
}

// ---------------------------------------------------------------------------
// Claude
// ---------------------------------------------------------------------------

/** Claude refuses an empty text block, a conversation that opens with the assistant, and (Haiku 5.5, Opus 5.5) a
 *  trailing assistant turn (prefill): those are left out. Consecutive same-role turns are fine (the API merges them). */
function claudeMessages(messages: ChatMsg[]): Anthropic.MessageParam[] {
  const kept = messages.filter((m) => String(m.content ?? "").trim() !== "");
  while (kept.length && kept[0].role === "assistant") kept.shift();
  while (kept.length && kept[kept.length - 1].role === "assistant") kept.pop();
  return kept.map((m) => ({ role: m.role, content: m.content }));
}

/** Opus and Sonnet 5.5 take the server-side refusal fallback (beta); Haiku has none. */
const takesFallback = (model: string): boolean => model.startsWith("claude-opus-") || model.startsWith("claude-sonnet-5-5");

type ClaudeReply = {
  content: Array<{ type: string; text?: string }>;
  stop_reason: string | null;
  usage: { input_tokens: number; output_tokens: number; cache_creation_input_tokens?: number | null; cache_read_input_tokens?: number | null };
};

/** A failed Claude call by the SDK's typed errors: a timeout; a 429 or an overload, to retry after its Retry-After; any
 *  other status; or no response at all (APIConnectionError has no status). */
function claudeFailure(e: unknown, apiKey: string): Attempt {
  if (e instanceof Anthropic.APIConnectionTimeoutError) return { kind: "timeout" };
  if (e instanceof Anthropic.APIError && e.status !== undefined) {
    const detail = shortDetail(e.message, apiKey);
    return RETRYABLE_STATUS.has(e.status)
      ? { kind: "retryable", status: e.status, retryAfterMs: retryAfterMs(e.headers), detail }
      : { kind: "http", status: e.status, detail };
  }
  return { kind: "http", detail: "connection failed" };
}

async function claudeAttempt(
  cfg: Extract<ProviderConfig, { provider: "anthropic" }>,
  client: Anthropic,
  req: LlmRequest,
  timeoutMs: number,
): Promise<Attempt> {
  const messages = claudeMessages(req.messages);
  if (!messages.length) return { kind: "http", status: 400, detail: "no message content" };
  const system = req.json ? `${req.system}\n\n${JSON_ONLY}` : req.system;
  const systemBlock: Anthropic.TextBlockParam = {
    type: "text",
    text: system,
    ...(req.cache ? { cache_control: { type: "ephemeral" as const } } : {}),
  };
  const maxTokens = req.maxTokens + THINKING_ROOM[cfg.effort];

  let reply: ClaudeReply;
  try {
    if (takesFallback(cfg.model)) {
      reply = await client.beta.messages.create({
        model: cfg.model,
        max_tokens: maxTokens,
        system: [systemBlock],
        messages,
        thinking: { type: "adaptive" },
        output_config: { effort: cfg.effort },
        betas: [FALLBACK_BETA],
        fallbacks: "default",
      }, { timeout: timeoutMs });
    } else {
      reply = await client.messages.create({
        model: cfg.model,
        max_tokens: maxTokens,
        system: [systemBlock],
        messages,
        thinking: { type: "adaptive" },
        output_config: { effort: cfg.effort },
      }, { timeout: timeoutMs });
    }
  } catch (e) {
    return claudeFailure(e, cfg.apiKey);
  }

  if (reply.stop_reason === "refusal") return { kind: "blocked" };
  // Only the text blocks: thinking blocks (and a fallback's switch-point block) are not part of the answer.
  const text = reply.content.flatMap((b) => (b.type === "text" && typeof b.text === "string" ? [b.text] : [])).join("").trim();
  if (!text) return { kind: "empty" };
  const u = reply.usage;
  return {
    kind: "ok",
    text,
    usage: { input: u.input_tokens + (u.cache_creation_input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0), output: u.output_tokens },
  };
}

// ---------------------------------------------------------------------------
// Gemini (OpenAI-compatible endpoint) — the request the functions sent before
// ---------------------------------------------------------------------------

/** Key order as the functions wrote it: model, temperature, max_tokens, response_format, messages. */
export function buildGeminiBody(req: LlmRequest, model: string): Record<string, unknown> {
  return {
    model,
    ...(req.temperature != null ? { temperature: req.temperature } : {}),
    max_tokens: req.maxTokens,
    ...(req.json ? { response_format: { type: "json_object" } } : {}),
    messages: [
      { role: "system", content: req.system },
      ...req.messages.map((m) => ({ role: m.role, content: m.content })),
    ],
  };
}

async function geminiAttempt(
  cfg: Extract<ProviderConfig, { provider: "gemini" }>,
  req: LlmRequest,
  fetchImpl: typeof fetch,
  timeoutMs: number,
): Promise<Attempt> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let res: Response;
  try {
    res = await fetchImpl(GEMINI_URL, {
      method: "POST",
      headers: { "content-type": "application/json", "authorization": "Bearer " + cfg.apiKey },
      body: JSON.stringify(buildGeminiBody(req, cfg.model)),
      signal: controller.signal,
    });
  } catch (e) {
    clearTimeout(timer);
    if (e && typeof e === "object" && (e as { name?: string }).name === "AbortError") return { kind: "timeout" };
    return { kind: "http", detail: "connection failed" };
  }

  try {
    if (!res.ok) {
      const detail = shortDetail(await res.text().catch(() => ""), cfg.apiKey);
      return RETRYABLE_STATUS.has(res.status)
        ? { kind: "retryable", status: res.status, retryAfterMs: retryAfterMs(res.headers), detail }
        : { kind: "http", status: res.status, detail };
    }
    let data: {
      choices?: Array<{ message?: { content?: unknown }; finish_reason?: unknown }>;
      usage?: { prompt_tokens?: number; completion_tokens?: number };
    } | null;
    try {
      data = await res.json();
    } catch (e) {
      if (e && typeof e === "object" && (e as { name?: string }).name === "AbortError") return { kind: "timeout" };
      return { kind: "empty" };
    }
    const choice = data?.choices?.[0];
    const text = String(choice?.message?.content ?? "").trim();
    if (!text) return choice?.finish_reason === "content_filter" ? { kind: "blocked" } : { kind: "empty" };
    return { kind: "ok", text, usage: { input: data?.usage?.prompt_tokens ?? 0, output: data?.usage?.completion_tokens ?? 0 } };
  } finally {
    clearTimeout(timer);
  }
}

// ---------------------------------------------------------------------------
// callLlm
// ---------------------------------------------------------------------------

function terminal(r: Exclude<Attempt, { kind: "ok" }>): Extract<LlmResult, { ok: false }> {
  switch (r.kind) {
    case "timeout": return { ok: false, reason: "timeout", detail: "timed out" };
    case "empty": return { ok: false, reason: "empty", detail: "empty reply" };
    case "blocked": return { ok: false, reason: "blocked", detail: "declined" };
    case "retryable":
    case "http": return { ok: false, reason: "http", status: r.status, detail: r.detail };
  }
}

/** One call to the configured provider, with one retry on 429/503/529. Never throws. */
export async function callLlm(req: LlmRequest, deps: CallDeps = {}): Promise<LlmResult> {
  const cfg = selectProvider(deps.env ?? Deno.env.toObject());
  if (!cfg) {
    console.error("llm: no provider (ANTHROPIC_API_KEY / GEMINI_API_KEY unset)");
    return { ok: false, reason: "no-provider" };
  }
  const fetchImpl = deps.fetch ?? fetch;
  const sleep = deps.sleep ?? ((ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms)));
  const timeoutMs = req.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  // The SDK's own retries are off (one retry happens here); the base URL is pinned so no env var redirects it.
  const client = cfg.provider === "anthropic"
    ? new Anthropic({ apiKey: cfg.apiKey, baseURL: ANTHROPIC_URL, maxRetries: 0, ...(deps.fetch ? { fetch: deps.fetch } : {}) })
    : null;
  const once = (): Promise<Attempt> =>
    cfg.provider === "anthropic" ? claudeAttempt(cfg, client!, req, timeoutMs) : geminiAttempt(cfg, req, fetchImpl, timeoutMs);

  let r = await once();
  if (r.kind === "retryable") {
    const wait = Math.min(RETRY_MAX_MS, Math.max(RETRY_MIN_MS, r.retryAfterMs ?? 0));
    console.warn(`llm: retry provider=${cfg.provider} model=${cfg.model} status=${r.status} wait_ms=${wait}`);
    await sleep(wait);
    r = await once();
  }

  if (r.kind !== "ok") {
    const failed = terminal(r);
    console.error(`llm: failed provider=${cfg.provider} model=${cfg.model} reason=${failed.reason} status=${failed.status ?? "none"}`);
    return failed;
  }
  console.log(`llm: ok provider=${cfg.provider} model=${cfg.model} in=${r.usage.input} out=${r.usage.output}`);
  return {
    ok: true,
    text: r.text,
    json: req.json ? extractJson(r.text) : null,
    provider: cfg.provider,
    model: cfg.model,
    usage: r.usage,
  };
}
