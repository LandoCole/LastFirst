// Shared LLM call functions for curator edge functions

import {
  type NormalizedLLMResponse,
  type ToolCall,
  type LLMProvider,
} from "./types.ts";

// --- Provider resolution ---

export function resolveProvider(model: string): LLMProvider {
  const lower = model.toLowerCase();
  if (lower.includes("gpt") || lower === "chatgpt") return "openai";
  if (lower.includes("gemini")) return "google";
  return "anthropic";
}

export function resolveModelId(model: string, provider: LLMProvider): string {
  const trimmed = model.trim();
  if (!trimmed) {
    switch (provider) {
      case "openai":
        return "gpt-5.4-nano";
      case "google":
        return "gemini-3.1-flash-lite";
      case "anthropic":
      default:
        return "claude-sonnet-4-20250514";
    }
  }

  const lower = trimmed.toLowerCase();
  switch (provider) {
    case "openai":
      return lower.includes("gpt") ? trimmed : "gpt-5.4-nano";
    case "google":
      return lower.includes("gemini") ? trimmed : "gemini-3.1-flash-lite";
    case "anthropic":
    default:
      return lower.includes("claude") ? trimmed : "claude-sonnet-4-20250514";
  }
}

// --- Tool format converters ---

interface ToolDefinition {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
}

function toOpenAITools(
  tools: ToolDefinition[]
): { type: string; function: { name: string; description: string; parameters: Record<string, unknown> } }[] {
  return tools.map((t) => ({
    type: "function",
    function: {
      name: t.name,
      description: t.description,
      parameters: t.input_schema,
    },
  }));
}

function toGeminiTools(
  tools: ToolDefinition[]
): Record<string, unknown>[] {
  return [
    {
      functionDeclarations: tools.map((t) => ({
        name: t.name,
        description: t.description,
        parameters: t.input_schema,
      })),
    },
  ];
}

// --- LLM call functions ---

export async function callAnthropic(
  systemPrompt: string,
  messages: { role: string; content: unknown }[],
  model = "claude-sonnet-4-20250514",
  tools?: ToolDefinition[],
  maxTokens = 4096,
  enableWebSearch = false
): Promise<NormalizedLLMResponse> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");

  const body: Record<string, unknown> = {
    model,
    max_tokens: maxTokens,
    system: systemPrompt,
    messages,
  };
  const allTools: Record<string, unknown>[] = [];
  if (enableWebSearch) {
    allTools.push({ type: "web_search_20250305", name: "web_search", max_uses: 3 });
  }
  if (tools?.length) allTools.push(...tools);
  if (allTools.length > 0) body.tools = allTools;

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Anthropic API error ${res.status}: ${err}`);
  }

  const data = await res.json();
  let content = "";
  const toolCalls: ToolCall[] = [];
  const rawContent: Record<string, unknown>[] = data.content ?? [];

  for (const block of rawContent) {
    if (block.type === "text") {
      content += (block as { text: string }).text;
    } else if (block.type === "tool_use") {
      toolCalls.push({
        id: block.id as string,
        name: block.name as string,
        input: (block.input ?? {}) as Record<string, unknown>,
      });
    }
  }

  return {
    content,
    toolCalls,
    stopReason: data.stop_reason ?? "end_turn",
    usage: data.usage,
    rawContent: enableWebSearch ? rawContent : undefined,
  };
}

export async function callOpenAI(
  systemPrompt: string,
  messages: { role: string; content: unknown }[],
  model = "gpt-5.4-nano",
  tools?: ToolDefinition[],
  maxTokens = 4096,
  enableWebSearch = false
): Promise<NormalizedLLMResponse> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) throw new Error("OPENAI_API_KEY not set");

  if (enableWebSearch) {
    // gpt-5.4-nano supports web search natively, no model swap needed
  }

  const oaiMessages = [
    { role: "system", content: systemPrompt },
    ...messages,
  ];

  const body: Record<string, unknown> = {
    model,
    max_tokens: maxTokens,
    messages: oaiMessages,
  };
  if (enableWebSearch) body.web_search_options = {};
  if (tools?.length) body.tools = toOpenAITools(tools);

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`OpenAI API error ${res.status}: ${err}`);
  }

  const data = await res.json();
  const choice = data.choices?.[0];
  const message = choice?.message;

  const toolCalls: ToolCall[] = (message?.tool_calls ?? []).map(
    (tc: { id: string; function: { name: string; arguments: string } }) => ({
      id: tc.id,
      name: tc.function.name,
      input: JSON.parse(tc.function.arguments),
    })
  );

  return {
    content: message?.content ?? "",
    toolCalls,
    stopReason: choice?.finish_reason === "tool_calls" ? "tool_use" : "end_turn",
    usage: data.usage
      ? {
          input_tokens: data.usage.prompt_tokens,
          output_tokens: data.usage.completion_tokens,
        }
      : undefined,
  };
}

export async function callGemini(
  systemPrompt: string,
  messages: { role: string; content: unknown }[],
  model = "gemini-3.1-flash-lite",
  tools?: ToolDefinition[],
  maxTokens = 4096,
  enableWebSearch = false
): Promise<NormalizedLLMResponse> {
  const apiKey = Deno.env.get("GOOGLE_AI_API_KEY");
  if (!apiKey) throw new Error("GOOGLE_AI_API_KEY not set");

  const geminiMessages = messages.map((m) => ({
    role: m.role === "assistant" ? "model" : "user",
    parts: [{ text: typeof m.content === "string" ? m.content : JSON.stringify(m.content) }],
  }));

  const geminiTools: Record<string, unknown>[] = tools?.length ? toGeminiTools(tools) : [];
  if (enableWebSearch) geminiTools.push({ google_search: {} });

  const body: Record<string, unknown> = {
    system_instruction: { parts: [{ text: systemPrompt }] },
    contents: geminiMessages,
    generationConfig: { maxOutputTokens: maxTokens },
  };
  if (geminiTools.length > 0) body.tools = geminiTools;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Gemini API error ${res.status}: ${err}`);
  }

  const data = await res.json();
  const candidate = data.candidates?.[0];
  const parts = candidate?.content?.parts ?? [];

  let content = "";
  const toolCalls: ToolCall[] = [];

  for (const part of parts) {
    if (part.text) {
      content += part.text;
    } else if (part.functionCall) {
      toolCalls.push({
        id: `gemini_${crypto.randomUUID()}`,
        name: part.functionCall.name,
        input: part.functionCall.args ?? {},
      });
    }
  }

  const finishReason = candidate?.finishReason;
  return {
    content,
    toolCalls,
    stopReason: finishReason === "STOP" ? "end_turn" : toolCalls.length > 0 ? "tool_use" : "end_turn",
    usage: data.usageMetadata
      ? {
          input_tokens: data.usageMetadata.promptTokenCount ?? 0,
          output_tokens: data.usageMetadata.candidatesTokenCount ?? 0,
        }
      : undefined,
  };
}

export async function callLLM(
  provider: LLMProvider,
  systemPrompt: string,
  messages: { role: string; content: unknown }[],
  model: string,
  tools?: ToolDefinition[],
  maxTokens = 4096,
  enableWebSearch = false
): Promise<NormalizedLLMResponse> {
  switch (provider) {
    case "openai":
      return callOpenAI(systemPrompt, messages, model, tools, maxTokens, enableWebSearch);
    case "google":
      return callGemini(systemPrompt, messages, model, tools, maxTokens, enableWebSearch);
    case "anthropic":
    default:
      return callAnthropic(systemPrompt, messages, model, tools, maxTokens, enableWebSearch);
  }
}
