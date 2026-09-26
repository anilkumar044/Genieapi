import { App } from "aws-cdk-lib";
import { MusingStack } from "../lib/musing-stack";

const app = new App();
const context = (key: string): string | undefined => {
  const value: unknown = app.node.tryGetContext(key);
  return value === undefined || value === null || value === "" ? undefined : String(value);
};

const bundleId = context("bundleId");
if (!bundleId) throw new Error("Set the iOS bundle ID: cdk deploy -c bundleId=com.yourname.musing");

const maxConcurrency = context("maxConcurrency");

new MusingStack(app, "MusingBackend", {
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },
  bundleId,
  modelId: context("modelId") ?? "anthropic.claude-opus-5",
  fallbackModelId: context("fallbackModelId") ?? "",
  bedrockRegion: context("bedrockRegion"),
  effort: context("effort") ?? "",
  dailyLimit: Number(context("dailyLimit") ?? 150),
  appleKeySecretName: context("appleKeySecretName"),
  maxConcurrency: maxConcurrency ? Number(maxConcurrency) : undefined,
});
