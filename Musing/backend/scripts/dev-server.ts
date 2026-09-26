// Runs the backend on your computer for testing the app in the iOS Simulator.
//
//   npm run dev
//
// Claude is called with your own credentials:
//   - Amazon Bedrock (default): uses your AWS login (`aws configure` / `aws sso login`); set AWS_REGION if needed.
//   - Or the Claude API directly: set ANTHROPIC_API_KEY.
// Users and usage live in memory, and the app can sign in with "Developer sign-in" (no Apple account needed).
import { randomBytes } from "node:crypto";
import { createServer } from "node:http";
import Anthropic, { BetaFallbackState, betaRefusalFallbackMiddleware } from "@anthropic-ai/sdk";
import { AnthropicBedrockMantle } from "@anthropic-ai/bedrock-sdk";
import { defaultProvider } from "@aws-sdk/credential-provider-node";
import type { LambdaFunctionURLEvent } from "aws-lambda";
import { verifyAppleIdentityToken } from "../src/apple";
import type { Config, Effort } from "../src/config";
import { createHandler } from "../src/handler";
import { MemoryUserStore } from "../src/memory-store";

const port = Number(process.env.PORT ?? 8787);
const useClaudeAPI = Boolean(process.env.ANTHROPIC_API_KEY);
const bedrockModel = process.env.MODEL_ID ?? "anthropic.claude-opus-5";
const fallbackModel = process.env.FALLBACK_MODEL_ID ?? "anthropic.claude-opus-4-8";
// The Claude API uses the same model names without Bedrock's `anthropic.` prefix.
const stripPrefix = (id: string) => (useClaudeAPI ? id.replace(/^anthropic\./, "") : id);

const config: Config = {
  tableName: "memory",
  sessionSecretArn: "memory",
  bundleId: process.env.APPLE_BUNDLE_ID ?? "com.example.musing",
  modelId: stripPrefix(bedrockModel),
  fallbackModelId: fallbackModel ? stripPrefix(fallbackModel) : undefined,
  bedrockRegion: process.env.AWS_REGION ?? "us-east-1",
  dailyLimit: Number(process.env.DAILY_LIMIT ?? 500),
  effort: (process.env.EFFORT ?? "medium") as Effort,
};

const middleware = config.fallbackModelId ? [betaRefusalFallbackMiddleware([{ model: config.fallbackModelId }])] : [];
const client = useClaudeAPI
  ? new Anthropic({ middleware })
  : new AnthropicBedrockMantle({ awsRegion: config.bedrockRegion, middleware });

const CLAUDE_API_HINT = "⚠️  The Claude API rejected ANTHROPIC_API_KEY. Check the key at platform.claude.com.";
function bedrockHint(status: number): string {
  return status === 401
    ? "⚠️  Bedrock didn't accept your AWS credentials. Run `aws sts get-caller-identity` to check your login, then restart `npm run dev`."
    : `⚠️  Your AWS identity isn't allowed to use ${config.modelId}. It needs the IAM permission bedrock-mantle:CreateInference, and the model must be enabled in the Bedrock console (Model access) in ${config.bedrockRegion}. Or try MODEL_ID=anthropic.claude-opus-4-8.`;
}

// Check the AWS login up front so a missing one is obvious.
if (!useClaudeAPI) {
  try {
    const credentials = await defaultProvider()();
    console.log(`AWS credentials found (access key …${credentials.accessKeyId.slice(-4)}).`);
  } catch {
    console.warn(
      "⚠️  No AWS credentials found. Run `aws configure` (or `aws sso login`) and restart,\n" +
        "   or use the Claude API instead: ANTHROPIC_API_KEY=sk-ant-... npm run dev",
    );
  }
}

const sessionKey = randomBytes(32);
const handler = createHandler({
  config,
  store: new MemoryUserStore(),
  sessionKey: async () => sessionKey,
  verifyApple: (token) => verifyAppleIdentityToken(token, config.bundleId),
  appleKey: async () => undefined,
  exchangeCode: async () => undefined,
  revokeToken: async () => true,
  createMessage: async (params) => {
    try {
      return await client.beta.messages.create(params, { fallbackState: new BetaFallbackState() });
    } catch (error) {
      if (error instanceof Anthropic.APIError && (error.status === 401 || error.status === 403)) {
        console.warn(useClaudeAPI ? CLAUDE_API_HINT : bedrockHint(error.status));
      }
      throw error;
    }
  },
  now: () => new Date(),
  allowDevAuth: true,
});

createServer((req, res) => {
  const chunks: Buffer[] = [];
  req.on("data", (chunk: Buffer) => chunks.push(chunk));
  req.on("end", async () => {
    const url = new URL(req.url ?? "/", "http://localhost");
    const event = {
      rawPath: url.pathname,
      headers: Object.fromEntries(Object.entries(req.headers).map(([key, value]) => [key, String(value)])),
      body: chunks.length ? Buffer.concat(chunks).toString("utf8") : undefined,
      isBase64Encoded: false,
      requestContext: { http: { method: req.method ?? "GET" } },
    } as unknown as LambdaFunctionURLEvent;
    const started = Date.now();
    const result = await handler(event);
    res.writeHead(result.statusCode ?? 200, result.headers as Record<string, string> | undefined);
    res.end(result.body ?? "");
    console.log(`${req.method} ${url.pathname} → ${result.statusCode} (${Date.now() - started} ms)`);
  });
}).listen(port, () => {
  console.log(`Musing dev server on http://localhost:${port}`);
  console.log(`Model: ${config.modelId} via ${useClaudeAPI ? "the Claude API" : `Amazon Bedrock (${config.bedrockRegion})`}`);
});
