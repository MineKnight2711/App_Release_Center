import type { AuthContext } from './auth';
import { ApiError, json, readJson, str } from './http';

// Tried in order. SEA-LION is tuned for Southeast Asian languages, Vietnamese
// included; Gemma 3 covers for it when it is unavailable.
const RELEASE_NOTE_MODELS = [
  '@cf/aisingapore/gemma-sea-lion-v4-27b-it',
  '@cf/google/gemma-3-12b-it',
] as const;

// The client caps commit history at 30k characters; the rest is its rules.
const MAX_INPUT_CHARS = 40_000;
const MAX_INSTRUCTIONS_CHARS = 4_000;
const MAX_OUTPUT_TOKENS = 700;

/**
 * Fallback for the app's Gemini release notes once that quota runs out. The
 * app sends the same instructions and input it would give Gemini.
 */
export async function generateReleaseNotes(
  request: Request,
  env: Env,
  auth: AuthContext,
): Promise<Response> {
  const body = await readJson(request);
  const instructions = str(body.instructions);
  const input = str(body.input);
  if (!input) {
    throw new ApiError(400, 'invalid-input', 'Release note input is required.');
  }
  if (input.length > MAX_INPUT_CHARS || instructions.length > MAX_INSTRUCTIONS_CHARS) {
    throw new ApiError(413, 'input-too-large', 'Release note input is too large.');
  }
  // The daily free allocation is shared by the whole account; keep one user
  // from spending it.
  const { success } = await env.AI_LIMITER.limit({ key: `release-notes:${auth.uid}` });
  if (!success) {
    throw new ApiError(429, 'too-many-requests', 'Too many release note requests. Try again in a minute.');
  }

  const messages = [
    ...(instructions ? [{ role: 'system', content: instructions }] : []),
    { role: 'user', content: input },
  ];
  let lastError: unknown = 'empty response';
  for (const model of RELEASE_NOTE_MODELS) {
    try {
      const output = await env.AI.run(model, {
        messages,
        max_tokens: MAX_OUTPUT_TOKENS,
        temperature: 0.25,
      });
      const text = outputText(output);
      if (text) return json({ text, model });
    } catch (error) {
      if (isQuotaError(error)) {
        throw new ApiError(429, 'ai-quota-exceeded', 'Workers AI daily free allocation is used up.');
      }
      lastError = error;
    }
  }
  console.error('Workers AI release notes failed', lastError);
  throw new ApiError(502, 'ai-unavailable', 'Workers AI could not generate release notes.');
}

/** Gemma answers in `response`; SEA-LION in OpenAI-style `choices`. */
function outputText(output: unknown): string {
  if (!output || typeof output !== 'object') return '';
  const record = output as { response?: unknown; choices?: unknown };
  if (typeof record.response === 'string') return record.response.trim();
  if (Array.isArray(record.choices)) {
    const first = record.choices[0] as { message?: { content?: unknown }; text?: unknown } | undefined;
    const content = first?.message?.content ?? first?.text;
    if (typeof content === 'string') return content.trim();
  }
  return '';
}

/** Workers AI reports a spent daily free allocation as error 4006. */
function isQuotaError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return /\b4006\b|daily free allocation/i.test(message);
}
