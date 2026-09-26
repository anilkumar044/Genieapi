import { z } from "zod";
import type {
  BetaContentBlock,
  BetaMessage,
  BetaMessageParam,
  BetaTool,
  MessageCreateParamsNonStreaming,
} from "@anthropic-ai/sdk/resources/beta/messages/messages";
import type { Config } from "./config";

// MARK: - Tools
//
// Every tool runs on the person's iPhone, not here. The backend only tells Claude which tools exist;
// Claude's tool calls go back to the app, which runs reads right away and asks the person before any action.

const iso = (what: string) => ({
  type: "string",
  description: `${what}, ISO 8601 with the person's UTC offset, e.g. 2026-09-26T18:30:00-07:00`,
});

function tool(name: string, description: string, properties: Record<string, unknown>, required: string[]): BetaTool {
  return {
    name,
    description,
    input_schema: { type: "object", properties, required, additionalProperties: false },
  };
}

export const TOOLS = {
  calendar_list_events: tool(
    "calendar_list_events",
    "List events on the person's calendars between two times (at most 62 days apart). Use it to answer schedule questions and to check for conflicts before proposing or creating an event.",
    { start: iso("Range start"), end: iso("Range end") },
    ["start", "end"],
  ),
  calendar_create_event: tool(
    "calendar_create_event",
    "Create an event on the person's default calendar. The person must approve it first.",
    {
      title: { type: "string" },
      start: iso("Start time (for all-day events, a date like 2026-09-27)"),
      end: iso("End time (for all-day events, the last day)"),
      all_day: { type: "boolean" },
      location: { type: "string" },
      notes: { type: "string" },
    },
    ["title", "start", "end"],
  ),
  reminders_list: tool(
    "reminders_list",
    "List the person's reminders (incomplete ones by default).",
    { include_completed: { type: "boolean" } },
    [],
  ),
  reminders_create: tool(
    "reminders_create",
    "Create a reminder, optionally with a due time that triggers an alert. The person must approve it first.",
    { title: { type: "string" }, due: iso("Due time"), notes: { type: "string" } },
    ["title"],
  ),
  reminders_complete: tool(
    "reminders_complete",
    "Mark a reminder as completed, using the id from reminders_list. The person must approve it first.",
    { reminder_id: { type: "string" } },
    ["reminder_id"],
  ),
  contacts_search: tool(
    "contacts_search",
    "Search the person's contacts by name to find phone numbers and email addresses.",
    { query: { type: "string" } },
    ["query"],
  ),
  compose_email: tool(
    "compose_email",
    "Open an email draft for the person to review and send themselves. You cannot send email directly.",
    {
      to: { type: "array", items: { type: "string" }, description: "Email addresses" },
      subject: { type: "string" },
      body: { type: "string" },
    },
    ["to", "subject", "body"],
  ),
  compose_message: tool(
    "compose_message",
    "Open a text message draft (iMessage/SMS) for the person to review and send themselves.",
    {
      to: { type: "array", items: { type: "string" }, description: "Phone numbers or iMessage addresses" },
      body: { type: "string" },
    },
    ["to", "body"],
  ),
  open_link: tool(
    "open_link",
    "Open a web link on the phone, such as a reservation page, map or search. Only use URLs you are confident exist; for anything else use a search URL like https://www.google.com/search?q=… or https://maps.apple.com/?q=…. The person must approve it first.",
    { url: { type: "string" }, label: { type: "string", description: "What the link is, e.g. 'OpenTable: Nopa'" } },
    ["url", "label"],
  ),
  memory_save: tool(
    "memory_save",
    "Remember a durable fact or preference about the person for future conversations (e.g. 'Prefers morning meetings'). Save only what they share or ask you to remember.",
    { fact: { type: "string" } },
    ["fact"],
  ),
  memory_forget: tool(
    "memory_forget",
    "Forget a saved memory, using its id from the memories list.",
    { memory_id: { type: "string" } },
    ["memory_id"],
  ),
} satisfies Record<string, BetaTool>;

export type ToolName = keyof typeof TOOLS;
export const TOOL_NAMES = Object.keys(TOOLS) as [ToolName, ...ToolName[]];

export const AGENT_SYSTEM_PROMPT = `You are Musing, a personal assistant that gets things done for the person using this iPhone app. You work through tools that run on their iPhone: their calendar, reminders and contacts, drafting emails and texts, opening links, and remembering preferences.

How you work:
- Figure out what the person wants, look things up with the read tools, then take the action. Check the calendar for conflicts before scheduling, and search contacts to find someone's address or number.
- Actions (creating events or reminders, completing reminders, opening links, email and text drafts) are shown to the person for approval before they happen. If they decline, respect it and don't retry the same action unless they ask.
- You can't send email or texts yourself: compose tools open a draft that the person reviews and sends.
- You can't browse the web or look things up online. When the person needs something from a website, give your best suggestion and offer a link to open.
- Each user message starts with a <context> block containing the current time, the person's time zone, which connectors are on, and saved memories. Always write times in tool inputs as ISO 8601 with the person's UTC offset.
- If a request needs a connector that is turned off, say which one to turn on in Settings.
- When the person shares a lasting preference or asks you to remember something, save it with memory_save.

Style: this is a phone screen, so be brief and friendly. Confirm what you did in a sentence or two. Use short lists when they help. Never show raw ids.`;

// MARK: - Request from the app

const ALLOWED_BLOCKS = new Set(["text", "image", "tool_use", "tool_result", "thinking", "redacted_thinking"]);

const BlockSchema = z.looseObject({ type: z.string() }).refine((block) => ALLOWED_BLOCKS.has(block.type), {
  message: "Unsupported content block type",
});

const MessageSchema = z.object({
  role: z.enum(["user", "assistant"]),
  content: z.union([z.string().min(1).max(100_000), z.array(BlockSchema).min(1).max(200)]),
});

export const AgentRequestSchema = z
  .object({
    messages: z.array(MessageSchema).min(1).max(400),
    tools: z.array(z.enum(TOOL_NAMES)).max(TOOL_NAMES.length).default([]),
  })
  .superRefine((request, ctx) => {
    if (request.messages[0]?.role !== "user") {
      ctx.addIssue({ code: "custom", message: "The conversation must start with a user message" });
    }
    if (request.messages.at(-1)?.role !== "user") {
      ctx.addIssue({ code: "custom", message: "The last message must come from the user" });
    }
  });

export type AgentRequest = z.infer<typeof AgentRequestSchema>;

export function buildAgentParams(request: AgentRequest, config: Config): MessageCreateParamsNonStreaming {
  const enabled = new Set(request.tools);
  // Keep tool order fixed so the cached prompt prefix stays stable between turns.
  const tools = TOOL_NAMES.filter((name) => enabled.has(name)).map((name) => TOOLS[name]);
  const modern = !config.modelId.includes("haiku");
  return {
    model: config.modelId,
    max_tokens: 16000,
    // Tools render before the system prompt, so this breakpoint caches both.
    system: [{ type: "text", text: AGENT_SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
    ...(tools.length > 0 ? { tools, tool_choice: { type: "auto" as const } } : {}),
    // The app stores Claude's replies verbatim and sends them back unchanged (thinking blocks included).
    messages: request.messages as unknown as BetaMessageParam[],
    ...(modern ? { thinking: { type: "adaptive" as const } } : {}),
    ...(modern && config.effort ? { output_config: { effort: config.effort } } : {}),
  };
}

export interface AgentReply {
  /** Claude's content blocks, to be appended to the conversation exactly as returned. */
  content: BetaContentBlock[];
  stopReason: BetaMessage["stop_reason"];
}

export function toAgentReply(message: BetaMessage): AgentReply {
  // `fallback` blocks only mark where the refusal fallback switched models; they aren't part of the conversation.
  return {
    content: message.content.filter((block) => block.type !== "fallback"),
    stopReason: message.stop_reason,
  };
}

export type CreateMessage = (params: MessageCreateParamsNonStreaming) => Promise<BetaMessage>;

export async function runAgentTurn(request: AgentRequest, config: Config, createMessage: CreateMessage): Promise<AgentReply> {
  return toAgentReply(await createMessage(buildAgentParams(request, config)));
}
