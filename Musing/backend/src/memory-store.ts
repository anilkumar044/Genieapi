import type { UserRecord, UserStore } from "./store";

/** In-memory UserStore for tests and the local dev server. Data is lost when the process exits. */
export class MemoryUserStore implements UserStore {
  readonly users = new Map<string, UserRecord>();
  readonly usage = new Map<string, number>();

  async upsertUser(userId: string, fields: UserRecord): Promise<void> {
    const existing = this.users.get(userId) ?? {};
    this.users.set(userId, fields.appleRefreshToken ? { ...existing, appleRefreshToken: fields.appleRefreshToken } : existing);
  }

  async getUser(userId: string): Promise<UserRecord | undefined> {
    return this.users.get(userId);
  }

  async consumeQuota(userId: string, day: string, limit: number): Promise<{ allowed: boolean; used: number }> {
    const key = `${userId}/${day}`;
    const used = this.usage.get(key) ?? 0;
    if (used >= limit) return { allowed: false, used };
    this.usage.set(key, used + 1);
    return { allowed: true, used: used + 1 };
  }

  async refundQuota(userId: string, day: string): Promise<void> {
    const key = `${userId}/${day}`;
    this.usage.set(key, Math.max(0, (this.usage.get(key) ?? 0) - 1));
  }

  async getUsage(userId: string, day: string): Promise<number> {
    return this.usage.get(`${userId}/${day}`) ?? 0;
  }

  async deleteUser(userId: string): Promise<void> {
    this.users.delete(userId);
    for (const key of [...this.usage.keys()]) {
      if (key.startsWith(`${userId}/`)) this.usage.delete(key);
    }
  }
}
