export const EFFORTS = ["low", "medium", "high", "xhigh", "max"] as const;
export type Effort = (typeof EFFORTS)[number];

export interface Config {
  tableName: string;
  sessionSecretArn: string;
  /** Optional: Secrets Manager secret holding the Sign in with Apple key (for token revocation). */
  appleKeySecretArn?: string;
  /** The iOS app's bundle ID; Apple identity tokens must be issued for it. */
  bundleId: string;
  /** Bedrock model ID, e.g. `anthropic.claude-opus-5`. */
  modelId: string;
  /** Model to retry on when the main model declines a request. Empty to disable. */
  fallbackModelId?: string;
  bedrockRegion: string;
  /** Assistant steps (model calls) each user may run per UTC day. */
  dailyLimit: number;
  /** Reasoning effort; omitted from requests when unset (e.g. for Haiku). */
  effort?: Effort;
}

function required(env: NodeJS.ProcessEnv, name: string): string {
  const value = env[name];
  if (!value) throw new Error(`Missing required environment variable ${name}`);
  return value;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const effort = env.EFFORT || undefined;
  if (effort && !(EFFORTS as readonly string[]).includes(effort)) {
    throw new Error(`EFFORT must be one of ${EFFORTS.join(", ")}`);
  }
  const dailyLimit = Number(env.DAILY_LIMIT ?? "150");
  if (!Number.isInteger(dailyLimit) || dailyLimit < 1) {
    throw new Error("DAILY_LIMIT must be a positive integer");
  }
  return {
    tableName: required(env, "TABLE_NAME"),
    sessionSecretArn: required(env, "SESSION_SECRET_ARN"),
    appleKeySecretArn: env.APPLE_KEY_SECRET_ARN || undefined,
    bundleId: required(env, "APPLE_BUNDLE_ID"),
    modelId: required(env, "MODEL_ID"),
    fallbackModelId: env.FALLBACK_MODEL_ID || undefined,
    bedrockRegion: env.BEDROCK_REGION || required(env, "AWS_REGION"),
    dailyLimit,
    effort: effort as Effort | undefined,
  };
}
