import { SignJWT, jwtVerify } from "jose";

const ISSUER = "musing-backend";
const AUDIENCE = "musing-app";
export const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30;

/** Issues the app's own session token after Sign in with Apple succeeds. */
export async function issueSession(
  userId: string,
  key: Uint8Array,
  now: Date = new Date(),
): Promise<{ token: string; expiresAt: string }> {
  const issuedAt = Math.floor(now.getTime() / 1000);
  const expiresAt = issuedAt + SESSION_TTL_SECONDS;
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userId)
    .setIssuer(ISSUER)
    .setAudience(AUDIENCE)
    .setIssuedAt(issuedAt)
    .setExpirationTime(expiresAt)
    .sign(key);
  return { token, expiresAt: new Date(expiresAt * 1000).toISOString() };
}

/** Returns the user ID for a valid session token, or null. */
export async function verifySession(token: string, key: Uint8Array, now: Date = new Date()): Promise<string | null> {
  try {
    const { payload } = await jwtVerify(token, key, {
      issuer: ISSUER,
      audience: AUDIENCE,
      algorithms: ["HS256"],
      currentDate: now,
    });
    return typeof payload.sub === "string" && payload.sub ? payload.sub : null;
  } catch {
    return null;
  }
}
