const DEFAULT_MODEL = "gpt-5.6-luna";
const DEFAULT_TIMEOUT_MS = 110_000;
const DEFAULT_MAX_INPUT_CHARACTERS = 16_000;
const DEFAULT_MAX_OUTPUT_TOKENS = 1_000;
const ABSOLUTE_MAX_INPUT_CHARACTERS = 24_000;
const ABSOLUTE_MAX_OUTPUT_TOKENS = 2_000;
const DEFAULT_PROBE_TIMEOUT_MS = 10_000;

export class CloudAIConfigurationError extends Error {
  constructor(message) {
    super(message);
    this.name = "CloudAIConfigurationError";
  }
}

export class CloudAIProviderError extends Error {
  constructor(code, status = 503, retryAfter = 30) {
    super(code);
    this.name = "CloudAIProviderError";
    this.code = code;
    this.status = status;
    this.retryAfter = retryAfter;
  }
}

export class CloudAIInputLimitError extends Error {
  constructor(code = "input_limit_exceeded") {
    super(code);
    this.name = "CloudAIInputLimitError";
    this.code = code;
    this.status = 413;
  }
}

export async function probeOpenAIModel({ env, fetchImpl = fetch }) {
  const apiKey = String(env.OPENAI_API_KEY || "").trim();
  const model = String(env.BODYMODE_OPENAI_MODEL || DEFAULT_MODEL).trim();
  if (!apiKey) {
    return providerProbe(false, false, false, "missing_api_key");
  }
  if (!/^gpt-5\.6-luna(?:-|$)/.test(model)) {
    return providerProbe(true, false, false, "model_not_allowed");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEFAULT_PROBE_TIMEOUT_MS);
  try {
    const response = await fetchImpl(
      `https://api.openai.com/v1/models/${encodeURIComponent(model)}`,
      {
        method: "GET",
        headers: { authorization: `Bearer ${apiKey}` },
        signal: controller.signal,
      },
    );
    if (response.ok) return providerProbe(true, true, true, "ok");
    if (response.status === 401) return providerProbe(true, true, false, "invalid_api_key");
    if (response.status === 403) return providerProbe(true, true, false, "insufficient_permission");
    if (response.status === 404) return providerProbe(true, true, true, "model_unavailable");
    if (response.status === 429) return providerProbe(true, true, true, "provider_rate_limited");
    return providerProbe(true, true, false, "provider_unavailable");
  } catch (error) {
    return providerProbe(
      true,
      false,
      false,
      error?.name === "AbortError" ? "provider_timeout" : "provider_unreachable",
    );
  } finally {
    clearTimeout(timeout);
  }
}

export async function requestLunaJSON({
  env,
  developerPrompt,
  userContent,
  schemaName,
  schema,
  reasoningEffort = "low",
  maxInputCharacters = DEFAULT_MAX_INPUT_CHARACTERS,
  maxOutputTokens = DEFAULT_MAX_OUTPUT_TOKENS,
  fetchImpl = fetch,
}) {
  const apiKey = String(env.OPENAI_API_KEY || "").trim();
  if (!apiKey) {
    throw new CloudAIConfigurationError("OPENAI_API_KEY is required");
  }

  const model = String(env.BODYMODE_OPENAI_MODEL || DEFAULT_MODEL).trim();
  if (!/^gpt-5\.6-luna(?:-|$)/.test(model)) {
    throw new CloudAIConfigurationError("BODYMODE_OPENAI_MODEL must use GPT-5.6 Luna");
  }

  const inputLimit = boundedInteger(
    maxInputCharacters,
    DEFAULT_MAX_INPUT_CHARACTERS,
    1,
    ABSOLUTE_MAX_INPUT_CHARACTERS,
  );
  if (textInputCharacterCount(userContent) > inputLimit) {
    throw new CloudAIInputLimitError();
  }
  const outputLimit = boundedInteger(
    maxOutputTokens,
    DEFAULT_MAX_OUTPUT_TOKENS,
    128,
    ABSOLUTE_MAX_OUTPUT_TOKENS,
  );

  const timeoutMs = boundedInteger(
    env.BODYMODE_OPENAI_TIMEOUT_MS,
    DEFAULT_TIMEOUT_MS,
    5_000,
    115_000,
  );
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetchImpl("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model,
        store: false,
        max_output_tokens: outputLimit,
        reasoning: { effort: reasoningEffort },
        input: [
          {
            role: "developer",
            content: [{ type: "input_text", text: developerPrompt }],
          },
          {
            role: "user",
            content: userContent,
          },
        ],
        text: {
          format: {
            type: "json_schema",
            name: schemaName,
            strict: true,
            schema,
          },
        },
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      throw providerErrorForStatus(response.status);
    }

    const payload = await response.json();
    const outputText = extractOutputText(payload);
    if (!outputText) {
      throw new CloudAIProviderError("empty_model_response");
    }

    try {
      return {
        data: JSON.parse(outputText),
        usage: normalizedUsage(payload.usage),
        model: String(payload.model || model),
        responseId: String(payload.id || ""),
      };
    } catch {
      throw new CloudAIProviderError("invalid_structured_response");
    }
  } catch (error) {
    if (
      error instanceof CloudAIConfigurationError ||
      error instanceof CloudAIInputLimitError ||
      error instanceof CloudAIProviderError
    ) {
      throw error;
    }
    if (error?.name === "AbortError") {
      throw new CloudAIProviderError("provider_timeout", 504, 30);
    }
    throw new CloudAIProviderError("provider_unreachable");
  } finally {
    clearTimeout(timeout);
  }
}

export function textInputCharacterCount(content) {
  if (!Array.isArray(content)) return 0;
  return content.reduce((total, item) => {
    if (item?.type !== "input_text") return total;
    return total + String(item.text || "").length;
  }, 0);
}

export function extractOutputText(payload) {
  if (!payload || !Array.isArray(payload.output)) return "";
  for (const item of payload.output) {
    if (!Array.isArray(item?.content)) continue;
    for (const content of item.content) {
      if (content?.type === "output_text" && typeof content.text === "string") {
        return content.text;
      }
    }
  }
  return "";
}

function providerProbe(configured, reachable, authenticated, status) {
  return {
    configured,
    reachable,
    authenticated,
    modelAvailable: status === "ok",
    status,
  };
}

function normalizedUsage(usage) {
  return {
    inputTokens: nonnegativeInteger(usage?.input_tokens),
    outputTokens: nonnegativeInteger(usage?.output_tokens),
    totalTokens: nonnegativeInteger(usage?.total_tokens),
    cachedInputTokens: nonnegativeInteger(usage?.input_tokens_details?.cached_tokens),
  };
}

function providerErrorForStatus(status) {
  if (status === 401 || status === 403) {
    return new CloudAIProviderError("provider_authentication_failed", 503, 60);
  }
  if (status === 429) {
    return new CloudAIProviderError("provider_rate_limited", 503, 30);
  }
  if (status >= 500) {
    return new CloudAIProviderError("provider_unavailable", 503, 30);
  }
  return new CloudAIProviderError("provider_rejected_request", 503, 30);
}

function boundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(minimum, Math.min(parsed, maximum));
}

function nonnegativeInteger(value) {
  const parsed = Number.parseInt(String(value ?? "0"), 10);
  return Number.isFinite(parsed) ? Math.max(0, parsed) : 0;
}
