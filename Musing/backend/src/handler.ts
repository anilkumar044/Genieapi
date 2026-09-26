import Anthropic, { BetaFallbackState, betaRefusalFallbackMiddleware } from "@anthropic-ai/sdk";
import { AnthropicBedrockMantle } from "@anthropic-ai/bedrock-sdk";
import { GetSecretValueCommand, SecretsManagerClient } from "@aws-sdk/client-secrets-manager";
import type { APIGatewayProxyStructuredResultV2, LambdaFunctionURLEvent } from "aws-lambda";
import { z } from "zod";
import { AIRequestSchema, runAction, type CreateMessage } from "./ai";
import {
  exchangeAuthorizationCode,
  revokeRefreshToken,
  verifyAppleIdentityToken,
  type AppleIdentity,
  type AppleSigningKey,
} from "./apple";
import { loadConfig, type Config } from "./config";
import { AppError } from "./errors";
import { issueSession, verifySession } from "./session";
import { DynamoUserStore, type UserStore } from "./store";

export interface Deps {
  config: Config;
  store: UserStore;
  sessionKey: () => Promise<Uint8Array>;
  verifyApple: (identityToken: string) => Promise<AppleIdentity>;
  /** Sign in with Apple key, when configured; enables token revocation on account deletion. */
  appleKey: () => Promise<AppleSigningKey | undefined>;
  exchangeCode: (code: string, key: AppleSigningKey) => Promise<string | undefined>;
  revokeToken: (refreshToken: string, key: AppleSigningKey) => Promise<boolean>;
  createMessage: CreateMessage;
  now: () => Date;
}

type Result = APIGatewayProxyStructuredResultV2;

const json = (statusCode: number, body: unknown): Result => ({
  statusCode,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

const failure = (error: AppError): Result => json(error.status, { error: { code: error.code, message: error.message } });

const utcDay = (date: Date) => date.toISOString().slice(0, 10);

function readBody(event: LambdaFunctionURLEvent): unknown {
  if (!event.body) return {};
  const raw = event.isBase64Encoded ? Buffer.from(event.body, "base64").toString("utf8") : event.body;
  try {
    return JSON.parse(raw);
  } catch {
    throw new AppError(400, "invalid_json", "The request body isn't valid JSON.");
  }
}

function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const result = schema.safeParse(value);
  if (!result.success) {
    const detail = result.error.issues.map((issue) => issue.message).join("; ");
    throw new AppError(400, "invalid_request", detail || "The request is invalid.");
  }
  return result.data;
}

const SignInSchema = z.object({
  identityToken: z.string().min(1).max(10_000),
  authorizationCode: z.string().max(1000).optional(),
});

/** Maps model-call failures to responses the app can act on. */
function modelFailure(error: unknown): AppError {
  if (error instanceof AppError) return error;
  if (error instanceof Anthropic.RateLimitError) {
    return new AppError(503, "busy", "The AI is busy right now. Please try again in a minute.");
  }
  if (error instanceof Anthropic.APIConnectionError) {
    return new AppError(503, "unavailable", "Couldn't reach the AI service. Please try again.");
  }
  if (error instanceof Anthropic.APIError) {
    console.error(JSON.stringify({ msg: "model_error", status: error.status, requestId: error.requestID }));
    return new AppError(502, "model_error", "The AI service returned an error. Please try again.");
  }
  console.error(JSON.stringify({ msg: "unexpected_error", error: String(error) }));
  return new AppError(500, "internal", "Something went wrong.");
}

export function createHandler(deps: Deps) {
  async function requireUser(event: LambdaFunctionURLEvent): Promise<string> {
    const header = event.headers?.authorization ?? event.headers?.Authorization ?? "";
    const token = header.startsWith("Bearer ") ? header.slice("Bearer ".length).trim() : "";
    const userId = token ? await verifySession(token, await deps.sessionKey(), deps.now()) : null;
    if (!userId) throw new AppError(401, "unauthorized", "Please sign in again.");
    return userId;
  }

  async function signIn(event: LambdaFunctionURLEvent): Promise<Result> {
    const body = parse(SignInSchema, readBody(event));
    const identity = await deps.verifyApple(body.identityToken);
    let appleRefreshToken: string | undefined;
    const key = await deps.appleKey();
    if (key && body.authorizationCode) {
      appleRefreshToken = await deps.exchangeCode(body.authorizationCode, key).catch(() => undefined);
    }
    const now = deps.now();
    await deps.store.upsertUser(identity.sub, { appleRefreshToken }, now);
    const session = await issueSession(identity.sub, await deps.sessionKey(), now);
    return json(200, { sessionToken: session.token, expiresAt: session.expiresAt, userId: identity.sub });
  }

  async function me(event: LambdaFunctionURLEvent): Promise<Result> {
    const userId = await requireUser(event);
    const used = await deps.store.getUsage(userId, utcDay(deps.now()));
    return json(200, { userId, usage: { used, limit: deps.config.dailyLimit } });
  }

  async function runAI(event: LambdaFunctionURLEvent): Promise<Result> {
    const userId = await requireUser(event);
    const request = parse(AIRequestSchema, readBody(event));
    const day = utcDay(deps.now());
    const quota = await deps.store.consumeQuota(userId, day, deps.config.dailyLimit);
    if (!quota.allowed) {
      throw new AppError(429, "quota_exceeded", `You've used all ${deps.config.dailyLimit} AI actions for today.`);
    }
    const started = Date.now();
    try {
      const result = await runAction(request, deps.config, deps.createMessage);
      console.log(JSON.stringify({ msg: "ai_ok", action: request.action, ms: Date.now() - started }));
      return json(200, { action: request.action, result, usage: { used: quota.used, limit: deps.config.dailyLimit } });
    } catch (error) {
      const appError = modelFailure(error);
      console.warn(JSON.stringify({ msg: "ai_failed", action: request.action, code: appError.code }));
      // Don't charge the person for our failures; a refusal still counts.
      if (appError.code !== "refused") await deps.store.refundQuota(userId, day);
      throw appError;
    }
  }

  async function deleteAccount(event: LambdaFunctionURLEvent): Promise<Result> {
    const userId = await requireUser(event);
    const [user, key] = await Promise.all([deps.store.getUser(userId), deps.appleKey()]);
    if (user?.appleRefreshToken && key) {
      const revoked = await deps.revokeToken(user.appleRefreshToken, key).catch(() => false);
      if (!revoked) console.warn(JSON.stringify({ msg: "apple_revoke_failed" }));
    }
    await deps.store.deleteUser(userId);
    return { statusCode: 204 };
  }

  return async function handler(event: LambdaFunctionURLEvent): Promise<Result> {
    const method = event.requestContext?.http?.method ?? "GET";
    const path = (event.rawPath || "/").replace(/\/+$/, "") || "/";
    try {
      switch (`${method} ${path}`) {
        case "GET /v1/health":
          return json(200, { ok: true, model: deps.config.modelId });
        case "POST /v1/auth/apple":
          return await signIn(event);
        case "GET /v1/me":
          return await me(event);
        case "POST /v1/ai":
          return await runAI(event);
        case "DELETE /v1/account":
          return await deleteAccount(event);
        default:
          return failure(new AppError(404, "not_found", "No such endpoint."));
      }
    } catch (error) {
      return failure(error instanceof AppError ? error : modelFailure(error));
    }
  };
}

// MARK: - Lambda wiring

const secrets = new SecretsManagerClient({});

async function readSecret(arn: string): Promise<string> {
  const { SecretString } = await secrets.send(new GetSecretValueCommand({ SecretId: arn }));
  if (!SecretString) throw new Error(`Secret ${arn} is empty`);
  return SecretString;
}

function once<T>(load: () => Promise<T>): () => Promise<T> {
  let value: Promise<T> | undefined;
  return () => {
    value ??= load().catch((error: unknown) => {
      value = undefined; // retry on the next request instead of caching the failure
      throw error;
    });
    return value;
  };
}

function defaultDeps(): Deps {
  const config = loadConfig();
  const client = new AnthropicBedrockMantle({
    awsRegion: config.bedrockRegion,
    timeout: 110_000,
    // Bedrock has no server-side `fallbacks`; this retries a declined request on the fallback model.
    middleware: config.fallbackModelId ? [betaRefusalFallbackMiddleware([{ model: config.fallbackModelId }])] : [],
  });
  const appleKey = once(async () => {
    if (!config.appleKeySecretArn) return undefined;
    return z
      .object({ teamId: z.string().min(1), keyId: z.string().min(1), privateKey: z.string().min(1) })
      .parse(JSON.parse(await readSecret(config.appleKeySecretArn)));
  });
  return {
    config,
    store: new DynamoUserStore(config.tableName),
    sessionKey: once(async () => new TextEncoder().encode(await readSecret(config.sessionSecretArn))),
    verifyApple: (token) => verifyAppleIdentityToken(token, config.bundleId),
    appleKey: () => appleKey().catch(() => undefined),
    exchangeCode: (code, key) => exchangeAuthorizationCode(code, config.bundleId, key),
    revokeToken: (token, key) => revokeRefreshToken(token, config.bundleId, key),
    // Each AI action is a standalone request, so each gets its own fallback state.
    createMessage: (params) => client.beta.messages.create(params, { fallbackState: new BetaFallbackState() }),
    now: () => new Date(),
  };
}

let lambdaHandler: ReturnType<typeof createHandler> | undefined;

export const handler = (event: LambdaFunctionURLEvent): Promise<Result> => {
  lambdaHandler ??= createHandler(defaultDeps());
  return lambdaHandler(event);
};
