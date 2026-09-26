import { SignJWT, createRemoteJWKSet, importPKCS8, jwtVerify, type JWTVerifyGetKey } from "jose";
import { AppError } from "./errors";

const APPLE_ISSUER = "https://appleid.apple.com";
const appleKeys = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

export interface AppleIdentity {
  /** Apple's stable, app-team-scoped user identifier. */
  sub: string;
  email?: string;
}

/** Verifies an identity token from Sign in with Apple on the device. */
export async function verifyAppleIdentityToken(
  token: string,
  bundleId: string,
  keys: JWTVerifyGetKey = appleKeys,
): Promise<AppleIdentity> {
  try {
    const { payload } = await jwtVerify(token, keys, {
      issuer: APPLE_ISSUER,
      audience: bundleId,
      algorithms: ["RS256"],
    });
    if (typeof payload.sub !== "string" || !payload.sub) throw new Error("missing sub");
    return { sub: payload.sub, email: typeof payload.email === "string" ? payload.email : undefined };
  } catch {
    throw new AppError(401, "invalid_apple_token", "Sign in with Apple could not be verified.");
  }
}

/** The Sign in with Apple private key from the Apple Developer portal (Keys → Sign in with Apple). */
export interface AppleSigningKey {
  teamId: string;
  keyId: string;
  /** Contents of the downloaded `.p8` file. */
  privateKey: string;
}

type Fetch = typeof fetch;

/** The short-lived client secret Apple's REST API expects, signed with your key. */
export async function makeClientSecret(key: AppleSigningKey, bundleId: string, now: Date = new Date()): Promise<string> {
  const privateKey = await importPKCS8(key.privateKey, "ES256");
  const issuedAt = Math.floor(now.getTime() / 1000);
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: key.keyId })
    .setIssuer(key.teamId)
    .setSubject(bundleId)
    .setAudience(APPLE_ISSUER)
    .setIssuedAt(issuedAt)
    .setExpirationTime(issuedAt + 300)
    .sign(privateKey);
}

/** Exchanges the one-time authorization code for a refresh token we can revoke on account deletion. */
export async function exchangeAuthorizationCode(
  code: string,
  bundleId: string,
  key: AppleSigningKey,
  fetchImpl: Fetch = fetch,
): Promise<string | undefined> {
  const response = await fetchImpl(`${APPLE_ISSUER}/auth/token`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: bundleId,
      client_secret: await makeClientSecret(key, bundleId),
      code,
      grant_type: "authorization_code",
    }),
  });
  if (!response.ok) {
    console.warn(JSON.stringify({ msg: "apple_code_exchange_failed", status: response.status }));
    return undefined;
  }
  const body = (await response.json()) as { refresh_token?: unknown };
  return typeof body.refresh_token === "string" ? body.refresh_token : undefined;
}

/** Revokes the user's Sign in with Apple grant, as Apple requires when an account is deleted. */
export async function revokeRefreshToken(
  refreshToken: string,
  bundleId: string,
  key: AppleSigningKey,
  fetchImpl: Fetch = fetch,
): Promise<boolean> {
  const response = await fetchImpl(`${APPLE_ISSUER}/auth/revoke`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: bundleId,
      client_secret: await makeClientSecret(key, bundleId),
      token: refreshToken,
      token_type_hint: "refresh_token",
    }),
  });
  return response.ok;
}
