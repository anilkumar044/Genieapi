import { ConditionalCheckFailedException, DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  BatchWriteCommand,
  DynamoDBDocumentClient,
  GetCommand,
  QueryCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";

export interface UserRecord {
  appleRefreshToken?: string;
}

/** Persistence for users and their daily AI usage. */
export interface UserStore {
  upsertUser(userId: string, fields: UserRecord, now: Date): Promise<void>;
  getUser(userId: string): Promise<UserRecord | undefined>;
  /** Atomically counts one AI action; refuses once `limit` is reached for `day`. */
  consumeQuota(userId: string, day: string, limit: number): Promise<{ allowed: boolean; used: number }>;
  refundQuota(userId: string, day: string): Promise<void>;
  getUsage(userId: string, day: string): Promise<number>;
  deleteUser(userId: string): Promise<void>;
}

const userKey = (userId: string) => `USER#${userId}`;
const usageKey = (day: string) => `USAGE#${day}`;
/** Usage rows expire on their own a couple of days after the day they count. */
const USAGE_TTL_SECONDS = 60 * 60 * 24 * 3;

export class DynamoUserStore implements UserStore {
  private readonly db: DynamoDBDocumentClient;

  constructor(
    private readonly tableName: string,
    client: DynamoDBClient = new DynamoDBClient({}),
  ) {
    this.db = DynamoDBDocumentClient.from(client, { marshallOptions: { removeUndefinedValues: true } });
  }

  async upsertUser(userId: string, fields: UserRecord, now: Date): Promise<void> {
    const names: Record<string, string> = { "#createdAt": "createdAt", "#lastSignInAt": "lastSignInAt" };
    const values: Record<string, unknown> = { ":now": now.toISOString() };
    let update = "SET #createdAt = if_not_exists(#createdAt, :now), #lastSignInAt = :now";
    if (fields.appleRefreshToken) {
      names["#refresh"] = "appleRefreshToken";
      values[":refresh"] = fields.appleRefreshToken;
      update += ", #refresh = :refresh";
    }
    await this.db.send(
      new UpdateCommand({
        TableName: this.tableName,
        Key: { pk: userKey(userId), sk: "PROFILE" },
        UpdateExpression: update,
        ExpressionAttributeNames: names,
        ExpressionAttributeValues: values,
      }),
    );
  }

  async getUser(userId: string): Promise<UserRecord | undefined> {
    const { Item } = await this.db.send(
      new GetCommand({ TableName: this.tableName, Key: { pk: userKey(userId), sk: "PROFILE" } }),
    );
    if (!Item) return undefined;
    return { appleRefreshToken: typeof Item.appleRefreshToken === "string" ? Item.appleRefreshToken : undefined };
  }

  async consumeQuota(userId: string, day: string, limit: number): Promise<{ allowed: boolean; used: number }> {
    try {
      const { Attributes } = await this.db.send(
        new UpdateCommand({
          TableName: this.tableName,
          Key: { pk: userKey(userId), sk: usageKey(day) },
          UpdateExpression: "SET #ttl = if_not_exists(#ttl, :ttl) ADD #count :one",
          ConditionExpression: "attribute_not_exists(#count) OR #count < :limit",
          ExpressionAttributeNames: { "#count": "count", "#ttl": "ttl" },
          ExpressionAttributeValues: {
            ":one": 1,
            ":limit": limit,
            ":ttl": Math.floor(Date.parse(`${day}T00:00:00Z`) / 1000) + USAGE_TTL_SECONDS,
          },
          ReturnValues: "UPDATED_NEW",
        }),
      );
      return { allowed: true, used: Number(Attributes?.count ?? 1) };
    } catch (error) {
      if (error instanceof ConditionalCheckFailedException) return { allowed: false, used: limit };
      throw error;
    }
  }

  async refundQuota(userId: string, day: string): Promise<void> {
    await this.db.send(
      new UpdateCommand({
        TableName: this.tableName,
        Key: { pk: userKey(userId), sk: usageKey(day) },
        UpdateExpression: "ADD #count :minusOne",
        ConditionExpression: "#count > :zero",
        ExpressionAttributeNames: { "#count": "count" },
        ExpressionAttributeValues: { ":minusOne": -1, ":zero": 0 },
      }),
    ).catch((error: unknown) => {
      if (!(error instanceof ConditionalCheckFailedException)) throw error;
    });
  }

  async getUsage(userId: string, day: string): Promise<number> {
    const { Item } = await this.db.send(
      new GetCommand({ TableName: this.tableName, Key: { pk: userKey(userId), sk: usageKey(day) } }),
    );
    return Number(Item?.count ?? 0);
  }

  async deleteUser(userId: string): Promise<void> {
    let startKey: Record<string, unknown> | undefined;
    do {
      const page = await this.db.send(
        new QueryCommand({
          TableName: this.tableName,
          KeyConditionExpression: "pk = :pk",
          ExpressionAttributeValues: { ":pk": userKey(userId) },
          ProjectionExpression: "pk, sk",
          ExclusiveStartKey: startKey,
        }),
      );
      const keys = (page.Items ?? []).map((item) => ({ pk: item.pk, sk: item.sk }));
      for (let i = 0; i < keys.length; i += 25) {
        let requests: Record<string, unknown>[] | undefined = keys
          .slice(i, i + 25)
          .map((Key) => ({ DeleteRequest: { Key } }));
        // Retry anything DynamoDB couldn't process in this batch.
        for (let attempt = 0; requests && requests.length > 0 && attempt < 5; attempt++) {
          const result = await this.db.send(new BatchWriteCommand({ RequestItems: { [this.tableName]: requests } }));
          requests = result.UnprocessedItems?.[this.tableName] as Record<string, unknown>[] | undefined;
        }
      }
      startKey = page.LastEvaluatedKey;
    } while (startKey);
  }
}
