import { SignJWT, createLocalJWKSet, decodeJwt, decodeProtectedHeader, exportJWK, exportPKCS8, generateKeyPair } from "jose";
import { describe, expect, it } from "vitest";
import { exchangeAuthorizationCode, makeClientSecret, verifyAppleIdentityToken } from "../src/apple";
import { AppError } from "../src/errors";

const BUNDLE = "com.example.musing";

async function appleKeys() {
  const { publicKey, privateKey } = await generateKeyPair("RS256");
  const jwk = { ...(await exportJWK(publicKey)), kid: "apple-test", alg: "RS256", use: "sig" };
  const sign = (claims: Record<string, unknown>, audience = BUNDLE, issuer = "https://appleid.apple.com") =>
    new SignJWT(claims)
      .setProtectedHeader({ alg: "RS256", kid: "apple-test" })
      .setIssuer(issuer)
      .setAudience(audience)
      .setIssuedAt()
      .setExpirationTime("10m")
      .sign(privateKey);
  return { keySet: createLocalJWKSet({ keys: [jwk] }), sign };
}

describe("Sign in with Apple", () => {
  it("accepts a valid identity token for our bundle id", async () => {
    const { keySet, sign } = await appleKeys();
    const token = await sign({ sub: "001234.abcd", email: "x@privaterelay.appleid.com" });
    await expect(verifyAppleIdentityToken(token, BUNDLE, keySet)).resolves.toEqual({
      sub: "001234.abcd",
      email: "x@privaterelay.appleid.com",
    });
  });

  it("rejects tokens for another app or issuer", async () => {
    const { keySet, sign } = await appleKeys();
    await expect(verifyAppleIdentityToken(await sign({ sub: "u" }, "com.other.app"), BUNDLE, keySet)).rejects.toBeInstanceOf(AppError);
    await expect(
      verifyAppleIdentityToken(await sign({ sub: "u" }, BUNDLE, "https://evil.example"), BUNDLE, keySet),
    ).rejects.toBeInstanceOf(AppError);
  });

  it("signs the client secret Apple's REST API expects", async () => {
    const { privateKey } = await generateKeyPair("ES256", { extractable: true });
    const key = { teamId: "TEAM123456", keyId: "KEY1234567", privateKey: await exportPKCS8(privateKey) };
    const secret = await makeClientSecret(key, BUNDLE);
    expect(decodeProtectedHeader(secret)).toMatchObject({ alg: "ES256", kid: "KEY1234567" });
    expect(decodeJwt(secret)).toMatchObject({ iss: "TEAM123456", sub: BUNDLE, aud: "https://appleid.apple.com" });

    let sentBody = "";
    const fakeFetch = (async (_url: unknown, init?: RequestInit) => {
      sentBody = String(init?.body);
      return new Response(JSON.stringify({ refresh_token: "r-123" }), { status: 200 });
    }) as typeof fetch;
    await expect(exchangeAuthorizationCode("code-1", BUNDLE, key, fakeFetch)).resolves.toBe("r-123");
    expect(sentBody).toContain("grant_type=authorization_code");
    expect(sentBody).toContain("code=code-1");
  });
});
