// Exercises the real AnthropicBedrockMantle client + refusal-fallback middleware against a local mock
// of the Bedrock Messages endpoint. Run: npx tsx scripts/mock-bedrock-check.ts
import { createServer } from "node:http";
import { BetaFallbackState, betaRefusalFallbackMiddleware } from "@anthropic-ai/sdk";
import { AnthropicBedrockMantle } from "@anthropic-ai/bedrock-sdk";
import { AgentRequestSchema, runAgentTurn } from "../src/agent";
import type { Config } from "../src/config";

const seen: { model: string; auth: string; path: string; hasCredit: boolean; beta: string }[] = [];
const server = createServer((req, res) => {
  let raw = "";
  req.on("data", (chunk) => (raw += chunk));
  req.on("end", () => {
    const body = JSON.parse(raw);
    seen.push({
      model: body.model,
      auth: String(req.headers.authorization ?? ""),
      path: req.url ?? "",
      hasCredit: "fallback_credit_token" in body,
      beta: String(req.headers["anthropic-beta"] ?? ""),
    });
    const base = { id: `msg_${seen.length}`, type: "message", role: "assistant", model: body.model, usage: { input_tokens: 10, output_tokens: 5 } };
    const reply =
      body.model === "anthropic.claude-opus-5"
        ? { ...base, content: [], stop_reason: "refusal", stop_details: { type: "refusal", category: null, explanation: null, fallback_credit_token: "credit-123", fallback_has_prefill_claim: false } }
        : { ...base, stop_reason: "tool_use", content: [{ type: "text", text: "Let me check." }, { type: "tool_use", id: "tu_1", name: "calendar_list_events", input: { start: "2026-09-26T00:00:00-07:00", end: "2026-09-27T00:00:00-07:00" } }] };
    res.writeHead(200, { "content-type": "application/json", "request-id": `req_${seen.length}` });
    res.end(JSON.stringify(reply));
  });
});
await new Promise<void>((resolve) => server.listen(0, resolve));
const port = (server.address() as { port: number }).port;

const config: Config = {
  tableName: "t", sessionSecretArn: "s", bundleId: "b", bedrockRegion: "us-east-1", dailyLimit: 5,
  modelId: "anthropic.claude-opus-5", fallbackModelId: "anthropic.claude-opus-4-8", effort: "medium",
};
const client = new AnthropicBedrockMantle({
  awsRegion: "us-east-1",
  baseURL: `http://127.0.0.1:${port}/anthropic`,
  awsAccessKey: "AKIDEXAMPLE",
  awsSecretAccessKey: "secret",
  maxRetries: 0,
  middleware: [betaRefusalFallbackMiddleware([{ model: config.fallbackModelId! }])],
});

const reply = await runAgentTurn(
  AgentRequestSchema.parse({
    tools: ["calendar_list_events"],
    messages: [{ role: "user", content: [{ type: "text", text: "What's on my calendar today?" }] }],
  }),
  config,
  (params) => client.beta.messages.create(params, { fallbackState: new BetaFallbackState() }),
);
server.close();

console.log("reply:", JSON.stringify(reply));
for (const call of seen) {
  console.log(`call -> ${call.path} model=${call.model} sigv4=${call.auth.startsWith("AWS4-HMAC-SHA256")} credit=${call.hasCredit} beta=${call.beta}`);
}
const ok =
  reply.stopReason === "tool_use" &&
  reply.content.some((block) => block.type === "tool_use") &&
  seen.length === 2 &&
  seen[0]!.model === "anthropic.claude-opus-5" &&
  seen[1]!.model === "anthropic.claude-opus-4-8" &&
  seen[1]!.hasCredit &&
  seen.every((call) => call.auth.startsWith("AWS4-HMAC-SHA256") && call.path.startsWith("/anthropic/v1/messages"));
console.log(ok ? "MOCK CHECK PASSED" : "MOCK CHECK FAILED");
process.exit(ok ? 0 : 1);
