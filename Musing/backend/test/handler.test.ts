import Anthropic from "@anthropic-ai/sdk";
import type { BetaMessage } from "@anthropic-ai/sdk/resources/beta/messages/messages";
import type { LambdaFunctionURLEvent } from "aws-lambda";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Config } from "../src/config";
import { AppError } from "../src/errors";
import { createHandler, type Deps } from "../src/handler";
import { MemoryUserStore } from "../src/memory-store";

const config: Config = {
  tableName: "t",
  sessionSecretArn: "s",
  bundleId: "com.example.musing",
  modelId: "anthropic.claude-opus-5",
  bedrockRegion: "us-east-1",
  dailyLimit: 2,
  effort: "medium",
};

const reply = (stop_reason: string, content: unknown[] = [{ type: "text", text: "Done!" }]) =>
  ({ id: "msg", type: "message", role: "assistant", model: config.modelId, stop_reason, content }) as unknown as BetaMessage;

function event(method: string, path: string, body?: unknown, token?: string): LambdaFunctionURLEvent {
  return {
    rawPath: path,
    headers: token ? { authorization: `Bearer ${token}` } : {},
    body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
    isBase64Encoded: false,
    requestContext: { http: { method } },
  } as unknown as LambdaFunctionURLEvent;
}

const turn = {
  tools: ["calendar_list_events"],
  messages: [{ role: "user", content: [{ type: "text", text: "What's on my calendar today?" }] }],
};

let store: MemoryUserStore;
let deps: Deps;
let handler: ReturnType<typeof createHandler>;

const body = (result: { body?: string }) => JSON.parse(String(result.body));

async function signIn(): Promise<string> {
  const response = await handler(event("POST", "/v1/auth/apple", { identityToken: "apple-token", authorizationCode: "code" }));
  expect(response.statusCode).toBe(200);
  return body(response).sessionToken;
}

beforeEach(() => {
  store = new MemoryUserStore();
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
    createMessage: vi.fn(async () => reply("end_turn")),
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
    expect(await signIn()).toBeTruthy();
    expect(store.users.get("apple-user-1")).toEqual({ appleRefreshToken: "apple-refresh" });
    expect((await handler(event("POST", "/v1/auth/apple", { identityToken: "forged" }))).statusCode).toBe(401);
  });

  it("keeps developer sign-in off unless explicitly allowed", async () => {
    expect((await handler(event("POST", "/v1/auth/dev", {}))).statusCode).toBe(404);
    const dev = createHandler({ ...deps, allowDevAuth: true });
    const response = await dev(event("POST", "/v1/auth/dev", { name: "sim" }));
    expect(response.statusCode).toBe(200);
    expect(body(response).userId).toBe("dev-sim");
    expect((await dev(event("POST", "/v1/agent", turn, body(response).sessionToken))).statusCode).toBe(200);
  });

  it("requires a session for agent and account routes", async () => {
    for (const [method, path] of [["POST", "/v1/agent"], ["GET", "/v1/me"], ["DELETE", "/v1/account"]] as const) {
      expect((await handler(event(method, path, turn, "garbage"))).statusCode).toBe(401);
    }
  });

  it("runs an agent turn, returning Claude's blocks and usage", async () => {
    vi.mocked(deps.createMessage).mockResolvedValueOnce(
      reply("tool_use", [{ type: "tool_use", id: "tu_1", name: "calendar_list_events", input: { start: "a", end: "b" } }]),
    );
    const token = await signIn();
    const response = await handler(event("POST", "/v1/agent", turn, token));
    expect(response.statusCode).toBe(200);
    expect(body(response)).toEqual({
      content: [{ type: "tool_use", id: "tu_1", name: "calendar_list_events", input: { start: "a", end: "b" } }],
      stopReason: "tool_use",
      usage: { used: 1, limit: 2 },
    });
    const params = vi.mocked(deps.createMessage).mock.calls[0]![0];
    expect(params.tools).toHaveLength(1);
  });

  it("enforces the daily limit", async () => {
    const token = await signIn();
    await handler(event("POST", "/v1/agent", turn, token));
    await handler(event("POST", "/v1/agent", turn, token));
    const third = await handler(event("POST", "/v1/agent", turn, token));
    expect(third.statusCode).toBe(429);
    expect(body(third).error.code).toBe("quota_exceeded");
    expect(deps.createMessage).toHaveBeenCalledTimes(2);
  });

  it("passes refusals through (counted) and refunds model failures", async () => {
    const token = await signIn();
    vi.mocked(deps.createMessage).mockResolvedValueOnce(reply("refusal", []));
    const refused = await handler(event("POST", "/v1/agent", turn, token));
    expect(refused.statusCode).toBe(200);
    expect(body(refused).stopReason).toBe("refusal");
    expect(await store.getUsage("apple-user-1", "2026-09-26")).toBe(1);

    vi.mocked(deps.createMessage).mockRejectedValueOnce(new Anthropic.RateLimitError(429, undefined, "slow", new Headers()));
    expect((await handler(event("POST", "/v1/agent", turn, token))).statusCode).toBe(503);
    vi.mocked(deps.createMessage).mockRejectedValueOnce(new Anthropic.BadRequestError(400, undefined, "bad", new Headers()));
    const invalid = await handler(event("POST", "/v1/agent", turn, token));
    expect(invalid.statusCode).toBe(400);
    expect(body(invalid).error.code).toBe("conversation_invalid");
    expect(await store.getUsage("apple-user-1", "2026-09-26")).toBe(1);
  });

  it("rejects invalid requests without spending quota", async () => {
    const token = await signIn();
    expect((await handler(event("POST", "/v1/agent", "{not json", token))).statusCode).toBe(400);
    expect((await handler(event("POST", "/v1/agent", { messages: [] }, token))).statusCode).toBe(400);
    expect((await handler(event("POST", "/v1/agent", "x".repeat(5_600_000), token))).statusCode).toBe(413);
    expect(await store.getUsage("apple-user-1", "2026-09-26")).toBe(0);
  });

  it("deletes the account and revokes the Apple grant", async () => {
    const token = await signIn();
    await handler(event("POST", "/v1/agent", turn, token));
    const response = await handler(event("DELETE", "/v1/account", undefined, token));
    expect(response.statusCode).toBe(204);
    expect(deps.revokeToken).toHaveBeenCalledWith("apple-refresh", expect.anything());
    expect(store.users.size).toBe(0);
    expect(store.usage.size).toBe(0);
  });
});
