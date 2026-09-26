import { describe, expect, it } from "vitest";
import { SESSION_TTL_SECONDS, issueSession, verifySession } from "../src/session";

const key = new TextEncoder().encode("test-signing-key-0123456789abcdef0123456789abcdef");

describe("session tokens", () => {
  it("round-trips the user id", async () => {
    const { token, expiresAt } = await issueSession("user-1", key);
    expect(await verifySession(token, key)).toBe("user-1");
    expect(Date.parse(expiresAt)).toBeGreaterThan(Date.now());
  });

  it("rejects tampered, foreign-key and expired tokens", async () => {
    const { token } = await issueSession("user-1", key);
    expect(await verifySession(token.slice(0, -2) + "xx", key)).toBeNull();
    expect(await verifySession(token, new TextEncoder().encode("another-key-0123456789abcdef0123456789"))).toBeNull();
    const later = new Date(Date.now() + (SESSION_TTL_SECONDS + 60) * 1000);
    expect(await verifySession(token, key, later)).toBeNull();
    expect(await verifySession("not-a-jwt", key)).toBeNull();
  });
});
