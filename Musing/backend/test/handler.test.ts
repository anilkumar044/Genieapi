import Anthropic from "@anthropic-ai/sdk";
import type { BetaMessage } from "@anthropic-ai/sdk/resources/beta/messages/messages";
import type { LambdaFunctionURLEvent } from "aws-lambda";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Config } from "../src/config";
import { AppError } from "../src/errors";
import { createHandler, type Deps } from "../src/handler";
import type { UserRecord, UserStore } from "../src/store";

class MemoryStore implements UserStore {
  users = new Map<string, UserRecord>();
  usage = new Map<string, number>();
  async upsertUser(userId: string, fields: UserRecord) {
    this.users.set(userId, { ...this.users.get(userId), ...Object.fromEntries(Object.entries(fields).filter(([, v]) => v)) });
  }
  async getUser(userId: string) {
    return this.users.get(userId);
  }
  async consumeQuota(userId: string, day: string, limit: number) {
    const key = `${userId}/${day}`;
    const used = this.usage.get(key) ?? 0;
    if (used >= limit) return { allowed: false, used };
    this.usage.set(key, used + 1);
    return { allowed: true, used: used + 1 };
  }
  async refundQuota(userId: string, day: string) {
    const key = `${userId}/${day}`;
    this.usage.set(key, Math.max(0, (this.usage.get(key) ?? 0) - 1));
  }
  async getUsage(userId: string, day: string) {
    return this.usage.get(`${userId}/${day}`) ?? 0;
  }
  async deleteUser(userId: string) {
    this.users.delete(userId);
    for (const key of this.usage.keys()) if (key.startsWith(`${userId}/`)) this.usage.delete(key);
  }
}

const config: Config = {
  tableName: "t",
  sessionSecretArn: "s",
  bundleId: "com.example.musing",
  modelId: "anthropic.claude-opus-5",
  bedrockRegion: "us-east-1",
  dailyLimit: 2,
  effort: "medium",
};

const toolReply = (input: unknown, stop_reason = "tool_use") =>
  ({
    id: "msg",
    type: "message",
    role: "assistant",
    model: config.modelId,
    stop_reason,
    content: stop_reason === "refusal" ? [] : [{ type: "tool_use", id: "t", name: "respond", input }],
  }) as unknown as BetaMessage;

function event(method: string, path: string, body?: unknown, token?: string): LambdaFunctionURLEvent {
  return {
    rawPath: path,
    headers: token ? { authorization: `Bearer ${token}` } : {},
    body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
    isBase64Encoded: false,
    requestContext: { http: { method } },
  } as unknown as LambdaFunctionURLEvent;
}

const summarize = {
  action: "summarize",
  board: { title: "Ideas", cards: [{ id: "card-1", kind: "text", text: "Launch in May" }] },
};

let store: MemoryStore;
let deps: Deps;
let handler: ReturnType<typeof createHandler>;

async function signIn(): Promise<string> {
  const response = await handler(event("POST", "/v1/auth/apple", { identityToken: "apple-token", authorizationCode: "code" }));
  expect(response.statusCode).toBe(200);
  return JSON.parse(String(response.body)).sessionToken;
}

beforeEach(() => {
  store = new MemoryStore();
  deps = {
    config,
    store,
    sessionKey: async () => new TextEncoder().encode("k".repeat(64)),
    verifyApple: async (token) => {
      if (token !== "apple-token") throw new AppError(401, "invalid_apple_token", "bad");
      return { sub: "apple-user-1" };
    },
    appleKey: async () => ({ teamId: "T", keyId: "K", privateKey: "P" }),
    exchangeCode: vi.fn(async () => "apple-refresh"),
    revokeToken: vi.fn(async () => true),
    createMessage: vi.fn(async () => toolReply({ title: "Launch", summary: "Ship in May." })),
    now: () => new Date("2026-09-26T12:00:00Z"),
  };
  handler = createHandler(deps);
});

describe("handler", () => {
  it("serves health and 404s unknown routes", async () => {
    expect((await handler(event("GET", "/v1/health"))).statusCode).toBe(200);
    expect((await handler(event("GET", "/v1/nope"))).statusCode).toBe(404);
  });

  it("signs in with Apple and stores the refresh token for later revocation", async () => {
    const token = await signIn();
    expect(token).toBeTruthy();
    expect(store.users.get("apple-user-1")).toEqual({ appleRefreshToken: "apple-refresh" });
    const bad = await handler(event("POST", "/v1/auth/apple", { identityToken: "forged" }));
    expect(bad.statusCode).toBe(401);
  });

  it("requires a session for AI and account routes", async () => {
    for (const [method, path] of [["POST", "/v1/ai"], ["GET", "/v1/me"], ["DELETE", "/v1/account"]] as const) {
      const response = await handler(event(method, path, summarize, "garbage"));
      expect(response.statusCode).toBe(401);
    }
  });

  it("runs an AI action and counts usage", async () => {
    const token = await signIn();
    const response = await handler(event("POST", "/v1/ai", summarize, token));
    expect(response.statusCode).toBe(200);
    expect(JSON.parse(String(response.body))).toEqual({
      action: "summarize",
      result: { title: "Launch", summary: "Ship in May." },
      usage: { used: 1, limit: 2 },
    });
    const me = JSON.parse(String((await handler(event("GET", "/v1/me", undefined, token))).body));
    expect(me.usage).toEqual({ used: 1, limit: 2 });
  });

  it("enforces the daily limit", async () => {
    const token = await signIn();
    await handler(event("POST", "/v1/ai", summarize, token));
    await handler(event("POST", "/v1/ai", summarize, token));
    const third = await handler(event("POST", "/v1/ai", summarize, token));
    expect(third.statusCode).toBe(429);
    expect(JSON.parse(String(third.body)).error.code).toBe("quota_exceeded");
    expect(deps.createMessage).toHaveBeenCalledTimes(2);
  });

  it("refunds usage when the model fails, but not when it refuses", async () => {
    const token = await signIn();
    vi.mocked(deps.createMessage).mockRejectedValueOnce(
      new Anthropic.RateLimitError(429, undefined, "slow down", new Headers()),
    );
    const busy = await handler(event("POST", "/v1/ai", summarize, token));
    expect(busy.statusCode).toBe(503);
    expect(await store.getUsage("apple-user-1", "2026-09-26")).toBe(0);

    vi.mocked(deps.createMessage).mockResolvedValueOnce(toolReply(undefined, "refusal"));
    const refused = await handler(event("POST", "/v1/ai", summarize, token));
    expect(refused.statusCode).toBe(422);
    expect(await store.getUsage("apple-user-1", "2026-09-26")).toBe(1);
  });

  it("rejects invalid requests without spending quota", async () => {
    const token = await signIn();
    expect((await handler(event("POST", "/v1/ai", "{not json", token))).statusCode).toBe(400);
    expect((await handler(event("POST", "/v1/ai", { action: "ask", board: summarize.board }, token))).statusCode).toBe(400);
    expect(await store.getUsage("apple-user-1", "2026-09-26")).toBe(0);
  });

  it("deletes the account and revokes the Apple grant", async () => {
    const token = await signIn();
    await handler(event("POST", "/v1/ai", summarize, token));
    const response = await handler(event("DELETE", "/v1/account", undefined, token));
    expect(response.statusCode).toBe(204);
    expect(deps.revokeToken).toHaveBeenCalledWith("apple-refresh", expect.anything());
    expect(store.users.size).toBe(0);
    expect(store.usage.size).toBe(0);
  });
});
