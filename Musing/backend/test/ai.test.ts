import type { BetaMessage } from "@anthropic-ai/sdk/resources/beta/messages/messages";
import { describe, expect, it } from "vitest";
import { AIRequestSchema, buildParams, parseResult, renderBoard, runAction, type AIRequest } from "../src/ai";
import type { Config } from "../src/config";
import { AppError } from "../src/errors";

const config: Config = {
  tableName: "t",
  sessionSecretArn: "s",
  bundleId: "com.example.musing",
  modelId: "anthropic.claude-opus-5",
  fallbackModelId: "anthropic.claude-opus-4-8",
  bedrockRegion: "us-east-1",
  dailyLimit: 50,
  effort: "medium",
};

const board = {
  title: "Trip <plans>",
  cards: [
    { id: "A-uuid", kind: "text" as const, text: "Book flights & hotel" },
    { id: "B-uuid", kind: "text" as const, text: "Pack light" },
    { id: "C-uuid", kind: "link" as const, url: "https://example.com", linkTitle: "Guide" },
    { id: "D-uuid", kind: "board" as const, childTitle: "Food" },
    { id: "E-uuid", kind: "ink" as const },
  ],
};

function message(input: unknown, stop_reason: BetaMessage["stop_reason"] = "tool_use"): BetaMessage {
  return {
    id: "msg_1",
    type: "message",
    role: "assistant",
    model: config.modelId,
    stop_reason,
    content: input === undefined ? [] : [{ type: "tool_use", id: "tu_1", name: "respond", input }],
  } as unknown as BetaMessage;
}

const request = (extra: Partial<AIRequest>): AIRequest => AIRequestSchema.parse({ board, ...extra });

describe("request validation", () => {
  it("requires what each action needs", () => {
    expect(AIRequestSchema.safeParse({ action: "summarize", board }).success).toBe(true);
    expect(AIRequestSchema.safeParse({ action: "summarize", board: { title: "", cards: [] } }).success).toBe(false);
    expect(AIRequestSchema.safeParse({ action: "ask", board }).success).toBe(false);
    expect(AIRequestSchema.safeParse({ action: "expand", board, focusCardId: "C-uuid" }).success).toBe(false);
    expect(AIRequestSchema.safeParse({ action: "expand", board, focusCardId: "A-uuid" }).success).toBe(true);
    expect(AIRequestSchema.safeParse({ action: "handwriting", board }).success).toBe(false);
    expect(AIRequestSchema.safeParse({ action: "delete_everything", board }).success).toBe(false);
  });
});

describe("prompt building", () => {
  it("renders cards with short ids and escapes text", () => {
    const rendered = renderBoard(board);
    expect(rendered.xml).toContain('<board title="Trip &lt;plans&gt;">');
    expect(rendered.xml).toContain('<card id="c1" kind="text">Book flights &amp; hotel</card>');
    expect(rendered.xml).toContain("Guide — https://example.com");
    expect(rendered.xml).toContain("(nested board: Food)");
    expect(rendered.xml).toContain("(hand-drawn sketch)");
    expect(rendered.shortToApp.get("c2")).toBe("B-uuid");
  });

  it("uses adaptive thinking, effort and a single respond tool", () => {
    const { params } = buildParams(request({ action: "summarize" }), config);
    expect(params.model).toBe("anthropic.claude-opus-5");
    expect(params.thinking).toEqual({ type: "adaptive" });
    expect(params.output_config).toEqual({ effort: "medium" });
    expect(params.tool_choice).toEqual({ type: "auto" });
    expect(params.tools).toHaveLength(1);
  });

  it("omits thinking and effort for Haiku", () => {
    const { params } = buildParams(request({ action: "summarize" }), { ...config, modelId: "anthropic.claude-haiku-4-5" });
    expect(params.thinking).toBeUndefined();
    expect(params.output_config).toBeUndefined();
  });

  it("puts the image before the text and names the focus card", () => {
    const withImage = buildParams(
      request({ action: "photo_notes", image: { mediaType: "image/jpeg", data: "aGVsbG8=" } }),
      config,
    ).params;
    const content = withImage.messages[0]!.content as { type: string }[];
    expect(content.map((block) => block.type)).toEqual(["image", "text"]);

    const expand = buildParams(request({ action: "expand", focusCardId: "B-uuid" }), config).params;
    expect(JSON.stringify(expand.messages)).toContain("Expand on card c2");
  });
});

describe("result parsing", () => {
  const ctx = renderBoard(board);

  it("maps organize groups back to app ids, dropping unknown and duplicate ids", () => {
    const result = parseResult(
      message({
        groups: [
          { title: "Logistics", card_ids: ["c1", "c3", "c99"] },
          { title: "Packing", card_ids: ["c2", "c1"] },
          { title: "Empty", card_ids: ["c42"] },
        ],
      }),
      "organize",
      ctx,
    );
    expect(result.groups).toEqual([
      { title: "Logistics", cardIds: ["A-uuid", "C-uuid"] },
      { title: "Packing", cardIds: ["B-uuid"] },
    ]);
  });

  it("parses each action's shape", () => {
    expect(parseResult(message({ title: " T ", summary: "S" }), "summarize", ctx)).toEqual({ title: "T", summary: "S" });
    expect(parseResult(message({ ideas: ["a", " ", "b"] }), "expand", ctx)).toEqual({ ideas: ["a", "b"] });
    expect(parseResult(message({ text: "hello" }), "handwriting", ctx)).toEqual({ text: "hello" });
    expect(parseResult(message({ notes: ["n1"] }), "photo_notes", ctx)).toEqual({ notes: ["n1"] });
    expect(parseResult(message({ answer: "42" }), "ask", ctx)).toEqual({ answer: "42" });
  });

  it("reports refusals, missing tool calls and malformed input", () => {
    const code = (fn: () => unknown) => {
      try {
        fn();
      } catch (error) {
        return (error as AppError).code;
      }
    };
    expect(code(() => parseResult(message(undefined, "refusal"), "ask", ctx))).toBe("refused");
    expect(code(() => parseResult(message(undefined, "end_turn"), "ask", ctx))).toBe("no_result");
    expect(code(() => parseResult(message({ answer: 7 }), "ask", ctx))).toBe("bad_result");
    expect(code(() => parseResult(message({ groups: [{ title: "x", card_ids: ["c9"] }] }), "organize", ctx))).toBe(
      "bad_result",
    );
  });

  it("runs end to end against a fake model", async () => {
    const result = await runAction(request({ action: "ask", question: "What's first?" }), config, async (params) => {
      expect(JSON.stringify(params.messages)).toContain("What's first?");
      return message({ answer: "Book flights." });
    });
    expect(result).toEqual({ answer: "Book flights." });
  });
});
