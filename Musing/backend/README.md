# Musing backend (AWS + Claude on Amazon Bedrock)

The server side of the Musing assistant. The iPhone app never holds AWS credentials or talks to Bedrock
directly. It signs in with Apple, gets a session token from this backend, and sends the conversation for each
step. The backend adds the system prompt and the tools the person has enabled, calls Claude, and returns Claude's
reply. When Claude asks for a tool (calendar, reminders, contacts, drafts, links, memory), the **app** runs it on the
phone, after the person approves if it's an action, and sends the result with the next step.

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
| `src/agent.ts` | System prompt, tool definitions, request validation, reply cleanup |
| `src/apple.ts` | Verifies Sign in with Apple identity tokens; revokes Apple grants on account deletion |
| `src/session.ts` | The app's own 30-day session tokens |
| `src/store.ts` | DynamoDB: users and per-day usage limits |
| `lib/musing-stack.ts` | CDK infrastructure |
| `src/memory-store.ts` | In-memory user store for tests and the dev server |
| `scripts/dev-server.ts` | Local server for testing the app in the Simulator (`npm run dev`) |
| `test/` | Unit tests (auth, agent requests, handler flows, stack) |
| `scripts/mock-bedrock-check.ts` | Runs the real Bedrock client against a local mock, including refusal fallback |

### API

| Method & path | Auth | Purpose |
|---|---|---|
| `GET /v1/health` | none | Deployment check |
| `POST /v1/auth/apple` | Apple identity token | Exchange Sign in with Apple for a session token |
| `GET /v1/me` | session | Today's usage |
| `POST /v1/agent` | session | One assistant step: `{messages, tools}` → `{content, stopReason, usage}` |
| `POST /v1/auth/dev` | none | **Dev server only**: sign in without Apple. Returns 404 in AWS |
| `DELETE /v1/account` | session | Delete the account and its usage records, and revoke Sign in with Apple |

### How Claude is called

- Uses Anthropic's `AnthropicBedrockMantle` client (`@anthropic-ai/bedrock-sdk`) against Claude in Amazon
  Bedrock, signed with the Lambda role's credentials (IAM action `bedrock-mantle:CreateInference`).
- Default model: **`anthropic.claude-opus-5`** with adaptive thinking and `effort: medium`, which keeps
  replies fast enough for a phone.
- The app keeps the conversation and sends Claude's content blocks back exactly as received, thinking blocks
  included. The server is stateless, and chats never touch the server's database.
- The system prompt and tool definitions are marked for prompt caching, so repeated steps reuse that prefix.
- **Refusal fallback is on:** if the model declines a request, the SDK's client-side middleware retries it once on
  `anthropic.claude-opus-4-8`. Bedrock doesn't support the server-side `fallbacks` parameter. Set
  `fallbackModelId` to an empty string to turn this off.
- Each Claude call counts as one **assistant step** toward the daily limit. A request like “schedule lunch with Sam”
  might take 3–5 steps. Users aren't charged for server or model errors; a refused request still counts.

## Run locally

```bash
npm install
npm run dev                                   # Claude via Amazon Bedrock, using your AWS login
ANTHROPIC_API_KEY=sk-ant-... npm run dev      # or via the Claude API
```

The server listens on `http://localhost:8787`, keeps users in memory, and enables developer sign-in. Debug builds of
the app connect to it automatically. Optional environment variables: `MODEL_ID`, `FALLBACK_MODEL_ID`, `EFFORT`,
`AWS_REGION`, `PORT`, `DAILY_LIMIT`.

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
| `dailyLimit` | `150` | Assistant steps (Claude calls) per user per UTC day |
| `bedrockRegion` | stack region | Where Bedrock is called |
| `maxConcurrency` | unset | Reserved Lambda concurrency, as a hard cap on parallel AI calls |
| `appleKeySecretName` | unset | See above |

## Costs and spend guards

Everything is pay-per-use: Lambda, DynamoDB on-demand, and a Secrets Manager secret or two. Bedrock token usage
will be the main cost. Check the [Amazon Bedrock pricing page](https://aws.amazon.com/bedrock/pricing/) for current rates.
Built-in guards:
- `dailyLimit` per user.
- Optionally, `maxConcurrency`.
- A cap of 12 steps per request in the app.

Also set up an AWS Budgets alert on your account.

## Develop

```bash
npm run dev               # local server for the Simulator
npm test                  # unit tests
npm run build             # typecheck
npm run check:mock-bedrock  # real Bedrock SDK against a local mock (no AWS needed)
npx cdk synth -c bundleId=com.yourname.musing
```

`npx cdk destroy` removes the stack. The DynamoDB table is kept on purpose, so user records aren't lost by accident.
Delete it in the console if you really want it gone.
