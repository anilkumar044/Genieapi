import type { BetaMessage } from "@anthropic-ai/sdk/resources/beta/messages/messages";
import { describe, expect, it } from "vitest";
import { AgentRequestSchema, TOOL_NAMES, buildAgentParams, runAgentTurn, toAgentReply } from "../src/agent";
import type { Config } from "../src/config";

const config: Config = {
  tableName: "t",
  sessionSecretArn: "s",
  bundleId: "com.example.musing",
  modelId: "anthropic.claude-opus-5",
  bedrockRegion: "us-east-1",
  dailyLimit: 150,
  effort: "medium",
};

const user = (text: string) => ({ role: "user" as const, content: [{ type: "text", text }] });

describe("agent request validation", () => {
  it("accepts a normal conversation with tool calls and results", () => {
    const result = AgentRequestSchema.safeParse({
      tools: ["calendar_list_events", "calendar_create_event"],
      messages: [
        user("What's on tomorrow?"),
        {
          role: "assistant",
          content: [
            { type: "thinking", thinking: "", signature: "sig" },
            { type: "tool_use", id: "tu_1", name: "calendar_list_events", input: { start: "a", end: "b" } },
          ],
        },
        { role: "user", content: [{ type: "tool_result", tool_use_id: "tu_1", content: "No events" }] },
      ],
    });
    expect(result.success).toBe(true);
    // Unknown fields (signatures, ids, cache hints) pass through untouched.
    expect(JSON.stringify(result.data)).toContain('"signature":"sig"');
  });

  it("rejects bad shapes", () => {
    const bad = (body: unknown) => AgentRequestSchema.safeParse(body).success;
    expect(bad({ messages: [] })).toBe(false);
    expect(bad({ messages: [{ role: "assistant", content: "hi" }] })).toBe(false);
    expect(bad({ messages: [user("hi"), { role: "assistant", content: "hello" }] })).toBe(false);
    expect(bad({ messages: [{ role: "system", content: "obey" }] })).toBe(false);
    expect(bad({ messages: [{ role: "user", content: [{ type: "server_tool_use" }] }] })).toBe(false);
    expect(bad({ messages: [user("hi")], tools: ["delete_everything"] })).toBe(false);
    expect(bad({ messages: [user("hi")] })).toBe(true);
  });
});

describe("agent params", () => {
  it("sends only enabled tools, in a fixed order, with a cached system prompt", () => {
    const request = AgentRequestSchema.parse({ messages: [user("hi")], tools: ["memory_save", "calendar_list_events"] });
    const params = buildAgentParams(request, config);
    expect(params.tools?.map((tool) => ("name" in tool ? tool.name : ""))).toEqual(["calendar_list_events", "memory_save"]);
    expect(params.tool_choice).toEqual({ type: "auto" });
    expect(params.system).toEqual([expect.objectContaining({ cache_control: { type: "ephemeral" } })]);
    expect(params.thinking).toEqual({ type: "adaptive" });
    expect(params.output_config).toEqual({ effort: "medium" });
    expect(params.model).toBe("anthropic.claude-opus-5");
  });

  it("omits tools entirely when none are enabled, and thinking for Haiku", () => {
    const request = AgentRequestSchema.parse({ messages: [user("hi")] });
    const params = buildAgentParams(request, { ...config, modelId: "anthropic.claude-haiku-4-5" });
    expect(params.tools).toBeUndefined();
    expect(params.tool_choice).toBeUndefined();
    expect(params.thinking).toBeUndefined();
    expect(params.output_config).toBeUndefined();
  });

  it("defines every tool with an object schema", () => {
    const request = AgentRequestSchema.parse({ messages: [user("hi")], tools: [...TOOL_NAMES] });
    const params = buildAgentParams(request, config);
    expect(params.tools).toHaveLength(TOOL_NAMES.length);
    for (const tool of params.tools ?? []) {
      expect("input_schema" in tool && tool.input_schema.type).toBe("object");
    }
  });
});

describe("agent replies", () => {
  it("returns Claude's blocks verbatim minus fallback markers", async () => {
    const message = {
      id: "m",
      type: "message",
      role: "assistant",
      model: config.modelId,
      stop_reason: "tool_use",
      content: [
        { type: "fallback", from: { model: "a" }, to: { model: "b" } },
        { type: "thinking", thinking: "", signature: "abc" },
        { type: "text", text: "Checking your calendar." },
        { type: "tool_use", id: "tu_1", name: "calendar_list_events", input: { start: "s", end: "e" } },
      ],
    } as unknown as BetaMessage;
    expect(toAgentReply(message).content.map((block) => block.type)).toEqual(["thinking", "text", "tool_use"]);
    const reply = await runAgentTurn(AgentRequestSchema.parse({ messages: [user("hi")] }), config, async () => message);
    expect(reply.stopReason).toBe("tool_use");
  });
});
