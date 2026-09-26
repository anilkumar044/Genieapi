# Musing backend (AWS + Claude on Amazon Bedrock)

The server side of Musing's AI features. The iPhone app never holds AWS credentials or talks to Bedrock
directly. It signs in with Apple, gets a session token from this backend, and sends one board at a time
when the person taps an AI action. The model's work happens here on AWS, not on the phone.

```
iPhone ──HTTPS──► Lambda function URL ──► Claude in Amazon Bedrock
                     │                      (bedrock-mantle Messages API)
                     ├── DynamoDB: users + daily usage counts
                     └── Secrets Manager: session signing key (+ optional Apple key)
```

## What's inside

| Path | What it does |
|---|---|
| `src/handler.ts` | Lambda entry point and routes (below) |
| `src/ai.ts` | The six AI actions: prompts, tool schemas, result validation |
| `src/apple.ts` | Verifies Sign in with Apple identity tokens; revokes Apple grants on account deletion |
| `src/session.ts` | The app's own 30-day session tokens |
| `src/store.ts` | DynamoDB: users and per-day usage limits |
| `lib/musing-stack.ts` | CDK infrastructure |
| `test/` | Unit tests (auth, prompts, parsing, handler flows, stack) |
| `scripts/mock-bedrock-check.ts` | Runs the real Bedrock client against a local mock, including refusal fallback |

### API

| Method & path | Auth | Purpose |
|---|---|---|
| `GET /v1/health` | none | Deployment check |
| `POST /v1/auth/apple` | Apple identity token | Exchange Sign in with Apple for a session token |
| `GET /v1/me` | session | Today's usage |
| `POST /v1/ai` | session | Run `summarize`, `organize`, `expand`, `handwriting`, `photo_notes` or `ask` |
| `DELETE /v1/account` | session | Delete the account and its usage records, and revoke Sign in with Apple |

### How Claude is called

- Uses Anthropic's `AnthropicBedrockMantle` client (`@anthropic-ai/bedrock-sdk`) against Claude in Amazon
  Bedrock, signed with the Lambda role's credentials (IAM action `bedrock-mantle:CreateInference`).
- Default model: **`anthropic.claude-opus-5`** with adaptive thinking and `effort: medium`, which keeps
  replies fast enough for a phone.
- Results come back through a `respond` tool call and are validated before they reach the app.
  Structured outputs aren't available on this Bedrock endpoint yet, so the backend uses tool calls instead.
- **Refusal fallback is on:** if the model declines a request, the SDK's client-side middleware retries it once on
  `anthropic.claude-opus-4-8`. Bedrock doesn't support the server-side `fallbacks` parameter. Set
  `fallbackModelId` to an empty string to turn this off.
- Users are never charged quota for server or model errors. A refused request still counts.

## Deploy

**You need:** an AWS account, the AWS CLI signed in (`aws configure` or `aws sso login`), and Node.js 22+.

1. **Check model access.** Open the Bedrock console → **Model access** in the region you'll deploy to.
   Claude Opus 5 has its own access criteria on Bedrock. If your account can't use it yet, deploy with
   `-c modelId=anthropic.claude-opus-4-8` (or `anthropic.claude-sonnet-5`), which are open to all Bedrock customers.
2. **Deploy:**
   ```bash
   cd Musing/backend
   npm install
   npx cdk bootstrap                 # once per AWS account/region
   npx cdk deploy -c bundleId=com.yourname.musing
   ```
   Use the same bundle ID as in Xcode. Apple identity tokens are only accepted for that app.
3. **Connect the app.** Copy the `ApiUrl` output into `Musing/Musing/AI/AIConfig.swift`:
   ```swift
   static let backendURLString = "https://abc123xyz.lambda-url.us-east-1.on.aws/"
   ```
4. **Check it:** `curl <ApiUrl>v1/health` should return `{"ok":true,...}`.

### Recommended: let account deletion revoke Sign in with Apple

Apple expects apps to revoke the user's Sign in with Apple grant when they delete their account. To enable it:

1. In the Apple Developer portal → **Certificates, Identifiers & Profiles → Keys**, create a key with
   **Sign in with Apple** enabled for your app's App ID, then download the `.p8` file. Note the Key ID and your Team ID.
2. Store the key in Secrets Manager:
   ```bash
   jq -n --arg teamId YOUR_TEAM_ID --arg keyId YOUR_KEY_ID --rawfile privateKey AuthKey_YOUR_KEY_ID.p8 \
     '{teamId: $teamId, keyId: $keyId, privateKey: $privateKey}' > apple-key.json
   aws secretsmanager create-secret --name musing/apple-signin-key --secret-string file://apple-key.json
   rm apple-key.json
   ```
3. Redeploy with `-c appleKeySecretName=musing/apple-signin-key`.

### Settings

Pass with `-c name=value` on `cdk deploy`, or set them in `cdk.json`.

| Setting | Default | Notes |
|---|---|---|
| `bundleId` | `com.example.musing` | **Required to change.** Must match Xcode |
| `modelId` | `anthropic.claude-opus-5` | Any Claude model ID on Bedrock, e.g. `anthropic.claude-sonnet-5` or `anthropic.claude-haiku-4-5` |
| `fallbackModelId` | `anthropic.claude-opus-4-8` | Used only when the main model declines; empty disables |
| `effort` | `medium` | `low` … `max`; higher means more thorough but slower and more tokens. Ignored for Haiku |
| `dailyLimit` | `50` | AI actions per user per UTC day |
| `bedrockRegion` | stack region | Where Bedrock is called |
| `maxConcurrency` | unset | Reserved Lambda concurrency, as a hard cap on parallel AI calls |
| `appleKeySecretName` | unset | See above |

## Costs and spend guards

Everything is pay-per-use: Lambda, DynamoDB on-demand, and a Secrets Manager secret or two. Bedrock token usage
will be the main cost. Check the [Amazon Bedrock pricing page](https://aws.amazon.com/bedrock/pricing/) for current rates.
Built-in guards:
- `dailyLimit` per user.
- Optionally, `maxConcurrency`.
- Images are downscaled on the phone before upload.

Also set up an AWS Budgets alert on your account.

## Develop

```bash
npm test                  # unit tests
npm run build             # typecheck
npm run check:mock-bedrock  # real Bedrock SDK against a local mock (no AWS needed)
npx cdk synth -c bundleId=com.yourname.musing
```

`npx cdk destroy` removes the stack. The DynamoDB table is kept on purpose, so user records aren't lost by accident.
Delete it in the console if you really want it gone.
