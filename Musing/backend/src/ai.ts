import { z } from "zod";
import type {
  BetaContentBlockParam,
  BetaMessage,
  BetaTool,
  MessageCreateParamsNonStreaming,
} from "@anthropic-ai/sdk/resources/beta/messages/messages";
import type { Config } from "./config";
import { AppError } from "./errors";

// MARK: - Request from the app

export const ACTIONS = ["summarize", "organize", "expand", "handwriting", "photo_notes", "ask"] as const;
export type Action = (typeof ACTIONS)[number];

const CardSchema = z.object({
  id: z.string().min(1).max(64),
  kind: z.enum(["text", "ink", "image", "link", "board"]),
  text: z.string().max(8000).optional(),
  url: z.string().max(2000).optional(),
  linkTitle: z.string().max(500).optional(),
  childTitle: z.string().max(200).optional(),
});

export const AIRequestSchema = z
  .object({
    action: z.enum(ACTIONS),
    board: z.object({
      title: z.string().max(200),
      cards: z.array(CardSchema).max(400),
    }),
    focusCardId: z.string().max(64).optional(),
    question: z.string().trim().min(1).max(1000).optional(),
    image: z
      .object({
        mediaType: z.enum(["image/jpeg", "image/png"]),
        // ~3.75 MB of image once decoded; the app downscales well below this.
        data: z.string().min(1).max(5_000_000),
      })
      .optional(),
  })
  .superRefine((request, ctx) => {
    const needs = (ok: boolean, message: string) => {
      if (!ok) ctx.addIssue({ code: "custom", message });
    };
    const focus = request.board.cards.find((card) => card.id === request.focusCardId);
    switch (request.action) {
      case "expand":
        needs(!!focus?.text?.trim(), "expand needs focusCardId pointing at a card with text");
        break;
      case "handwriting":
      case "photo_notes":
        needs(!!request.image, `${request.action} needs an image`);
        break;
      case "ask":
        needs(!!request.question, "ask needs a question");
        break;
      case "summarize":
      case "organize":
        needs(request.board.cards.length > 0, `${request.action} needs a board with cards`);
        break;
    }
  });

export type AIRequest = z.infer<typeof AIRequestSchema>;

// MARK: - Result for the app

export interface AIResult {
  title?: string;
  summary?: string;
  groups?: { title: string; cardIds: string[] }[];
  ideas?: string[];
  text?: string;
  notes?: string[];
  answer?: string;
}

// MARK: - Prompting

export const SYSTEM_PROMPT = `You are the thinking partner inside Musing, a visual canvas app where people spread out small cards — notes, sketches, photos, links and nested boards — to think.

You receive the contents of one board and a task. Deliver the result by calling the \`respond\` tool exactly once; never answer in plain text.

Write the way people write on cards: short, concrete, and in the same language the board is written in. Work only from what is on the board (and the image, when one is provided); do not invent facts about the person's work. Card ids like "c3" are references for you, never text to show the person.`;

/** Board cards are shown to the model with short ids ("c1", "c2", …) that map back to the app's ids. */
interface BoardContext {
  xml: string;
  shortToApp: Map<string, string>;
  appToShort: Map<string, string>;
}

function escapeXML(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

export function renderBoard(board: AIRequest["board"]): BoardContext {
  const shortToApp = new Map<string, string>();
  const appToShort = new Map<string, string>();
  const lines = board.cards.map((card, index) => {
    const shortID = `c${index + 1}`;
    shortToApp.set(shortID, card.id);
    appToShort.set(card.id, shortID);
    let body: string;
    switch (card.kind) {
      case "text":
        body = card.text?.trim() || "(empty note)";
        break;
      case "ink":
        body = card.text?.trim() ? card.text : "(hand-drawn sketch)";
        break;
      case "image":
        body = card.text?.trim() ? card.text : "(photo)";
        break;
      case "link":
        body = [card.linkTitle, card.url].filter(Boolean).join(" — ") || "(link)";
        break;
      case "board":
        body = `(nested board: ${card.childTitle || "Untitled"})`;
        break;
    }
    return `<card id="${shortID}" kind="${card.kind}">${escapeXML(body)}</card>`;
  });
  const xml = `<board title="${escapeXML(board.title)}">\n${lines.join("\n")}\n</board>`;
  return { xml, shortToApp, appToShort };
}

interface ActionSpec {
  instruction(request: AIRequest, board: BoardContext): string;
  tool: BetaTool;
  parse(input: unknown, board: BoardContext): AIResult;
}

const stringList = (min: number, max: number) => ({
  type: "array",
  items: { type: "string" },
  minItems: min,
  maxItems: max,
});

function respondTool(description: string, properties: Record<string, unknown>): BetaTool {
  return {
    name: "respond",
    description,
    input_schema: {
      type: "object",
      properties,
      required: Object.keys(properties),
      additionalProperties: false,
    },
  };
}

const cleanList = (items: string[]) => items.map((item) => item.trim()).filter(Boolean);

const SPECS: Record<Action, ActionSpec> = {
  summarize: {
    instruction: () =>
      "Summarize this board. Give it a short title (at most 6 words) and a summary of 2–5 short lines covering the main ideas, open questions and any decisions.",
    tool: respondTool("Return the board summary.", {
      title: { type: "string", description: "Short title, at most 6 words." },
      summary: { type: "string", description: "2–5 short lines, separated by newlines." },
    }),
    parse: (input) => {
      const { title, summary } = z.object({ title: z.string(), summary: z.string().min(1) }).parse(input);
      return { title: title.trim(), summary: summary.trim() };
    },
  },
  organize: {
    instruction: () =>
      "Organize this board: sort the cards into 2–6 themed groups so it is easier to scan. Give each group a title of 1–4 words. Use each card id at most once and only ids that appear on the board. Leave out cards that fit no group.",
    tool: respondTool("Return the card groups.", {
      groups: {
        type: "array",
        minItems: 1,
        maxItems: 8,
        items: {
          type: "object",
          properties: {
            title: { type: "string" },
            card_ids: { type: "array", items: { type: "string" } },
          },
          required: ["title", "card_ids"],
          additionalProperties: false,
        },
      },
    }),
    parse: (input, board) => {
      const { groups } = z
        .object({ groups: z.array(z.object({ title: z.string(), card_ids: z.array(z.string()) })) })
        .parse(input);
      const used = new Set<string>();
      const mapped = groups
        .map((group) => ({
          title: group.title.trim(),
          cardIds: group.card_ids.flatMap((shortID) => {
            const appID = board.shortToApp.get(shortID.trim());
            if (!appID || used.has(appID)) return [];
            used.add(appID);
            return [appID];
          }),
        }))
        .filter((group) => group.title && group.cardIds.length > 0);
      if (mapped.length === 0) throw new Error("no usable groups");
      return { groups: mapped };
    },
  },
  expand: {
    instruction: (request, board) =>
      `Expand on card ${board.appToShort.get(request.focusCardId ?? "")}: suggest 3–6 new ideas that build on it — next steps, angles, questions or examples. Each idea is one short note of at most 25 words. Use the rest of the board only as context and don't repeat what is already there.`,
    tool: respondTool("Return the new ideas.", { ideas: stringList(1, 8) }),
    parse: (input) => {
      const ideas = cleanList(z.object({ ideas: z.array(z.string()) }).parse(input).ideas);
      if (ideas.length === 0) throw new Error("no ideas");
      return { ideas: ideas.slice(0, 8) };
    },
  },
  handwriting: {
    instruction: () =>
      "The image is a hand-drawn card from this board. Transcribe any handwriting as plain text, keeping its line breaks. If it is a drawing without words, describe it in one short sentence that starts with \"Sketch:\".",
    tool: respondTool("Return the transcription.", { text: { type: "string" } }),
    parse: (input) => {
      const text = z.object({ text: z.string() }).parse(input).text.trim();
      if (!text) throw new Error("empty transcription");
      return { text };
    },
  },
  photo_notes: {
    instruction: () =>
      "The image is a photo on this board, such as a whiteboard, a page or a screenshot. Extract its key content as 1–8 separate short notes, one idea per note.",
    tool: respondTool("Return the notes.", { notes: stringList(1, 8) }),
    parse: (input) => {
      const notes = cleanList(z.object({ notes: z.array(z.string()) }).parse(input).notes);
      if (notes.length === 0) throw new Error("no notes");
      return { notes: notes.slice(0, 8) };
    },
  },
  ask: {
    instruction: (request) =>
      `Answer the person's question using this board.\n<question>${escapeXML(request.question ?? "")}</question>\nKeep the answer under about 120 words. If the board doesn't contain the answer, say so briefly and give your best suggestion.`,
    tool: respondTool("Return the answer.", { answer: { type: "string" } }),
    parse: (input) => {
      const answer = z.object({ answer: z.string() }).parse(input).answer.trim();
      if (!answer) throw new Error("empty answer");
      return { answer };
    },
  },
};

export function buildParams(request: AIRequest, config: Config): {
  params: MessageCreateParamsNonStreaming;
  board: BoardContext;
} {
  const spec = SPECS[request.action];
  const board = renderBoard(request.board);
  const content: BetaContentBlockParam[] = [];
  if (request.image) {
    content.push({
      type: "image",
      source: { type: "base64", media_type: request.image.mediaType, data: request.image.data },
    });
  }
  content.push({ type: "text", text: `${board.xml}\n\n<task>\n${spec.instruction(request, board)}\n</task>` });

  // Haiku 4.5 predates adaptive thinking and effort; newer models get both.
  const modern = !config.modelId.includes("haiku");
  const params: MessageCreateParamsNonStreaming = {
    model: config.modelId,
    max_tokens: 16000,
    system: SYSTEM_PROMPT,
    tools: [spec.tool],
    tool_choice: { type: "auto" },
    messages: [{ role: "user", content }],
    ...(modern ? { thinking: { type: "adaptive" } } : {}),
    ...(modern && config.effort ? { output_config: { effort: config.effort } } : {}),
  };
  return { params, board };
}

/** Pulls the `respond` tool call out of Claude's reply and validates it. */
export function parseResult(message: BetaMessage, action: Action, board: BoardContext): AIResult {
  if (message.stop_reason === "refusal") {
    throw new AppError(422, "refused", "Claude couldn't help with this request.");
  }
  const call = message.content.find((block) => block.type === "tool_use" && block.name === "respond");
  if (!call || call.type !== "tool_use") {
    const reason = message.stop_reason === "max_tokens" ? "The reply was too long." : "Claude didn't return a result.";
    throw new AppError(502, "no_result", reason);
  }
  try {
    return SPECS[action].parse(call.input, board);
  } catch {
    throw new AppError(502, "bad_result", "Claude's reply couldn't be understood. Please try again.");
  }
}

export type CreateMessage = (params: MessageCreateParamsNonStreaming) => Promise<BetaMessage>;

export async function runAction(request: AIRequest, config: Config, createMessage: CreateMessage): Promise<AIResult> {
  const { params, board } = buildParams(request, config);
  const message = await createMessage(params);
  return parseResult(message, request.action, board);
}
