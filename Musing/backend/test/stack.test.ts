import { App } from "aws-cdk-lib";
import { Match, Template } from "aws-cdk-lib/assertions";
import { describe, expect, it } from "vitest";
import { MusingStack } from "../lib/musing-stack";

describe("MusingStack", () => {
  it("wires the function, table, secret, Bedrock permission and public URL", () => {
    const app = new App();
    const stack = new MusingStack(app, "Test", {
      bundleId: "com.example.musing",
      modelId: "anthropic.claude-opus-5",
      fallbackModelId: "anthropic.claude-opus-4-8",
      effort: "medium",
      dailyLimit: 50,
      appleKeySecretName: "musing/apple-signin-key",
    });
    const template = Template.fromStack(stack);

    template.hasResourceProperties("AWS::Lambda::Function", {
      Runtime: "nodejs22.x",
      Architectures: ["arm64"],
      Environment: {
        Variables: Match.objectLike({
          APPLE_BUNDLE_ID: "com.example.musing",
          MODEL_ID: "anthropic.claude-opus-5",
          FALLBACK_MODEL_ID: "anthropic.claude-opus-4-8",
          DAILY_LIMIT: "50",
        }),
      },
    });
    template.hasResourceProperties("AWS::Lambda::Url", { AuthType: "NONE" });
    template.resourceCountIs("AWS::DynamoDB::GlobalTable", 1);
    template.resourceCountIs("AWS::SecretsManager::Secret", 1);

    const policies = JSON.stringify(template.findResources("AWS::IAM::Policy"));
    expect(policies).toContain("bedrock-mantle:CreateInference");
    expect(policies).toContain("secretsmanager:GetSecretValue");
  });
});
