export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export function json(data: unknown, status = 200): Response {
  return Response.json(data, { status });
}

export function noContent(): Response {
  return new Response(null, { status: 204 });
}

export function errorResponse(error: ApiError): Response {
  return json({ error: { code: error.code, message: error.message } }, error.status);
}

export async function readJson(request: Request): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new ApiError(400, 'invalid-json', 'Request body must be JSON.');
  }
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    throw new ApiError(400, 'invalid-json', 'Request body must be a JSON object.');
  }
  return body as Record<string, unknown>;
}

export function str(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

export function nowIso(): string {
  return new Date().toISOString();
}
