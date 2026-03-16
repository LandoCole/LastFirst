import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { callLLM, resolveModelId, resolveProvider } from "../_shared/llm.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface TextTransformSegment {
  id: string;
  text: string;
}

interface TextTransformRequest {
  mode: "summarize" | "custom";
  conciseness?: "brief" | "moderate" | "detailed";
  instructions?: string;
  unit_id: string;
  unit_title?: string | null;
  segments: TextTransformSegment[];
  model?: string | null;
}

interface TextTransformSegmentResponse {
  segment_id: string;
  transformed_text: string;
}

const SUMMARIZE_SYSTEM_PROMPT = `You are a text transformation engine for a reading app.
Output ONLY strict JSON in this format: {"segments":[{"segment_id":"...","transformed_text":"..."}]}.
No commentary, no markdown fences, no explanations.

GOAL: Summarize each input segment at the specified conciseness level while preserving segment boundaries.

CONCISENESS LEVELS:
- "brief": Compress to ~20% of original length. Keep only the core argument or key facts.
- "moderate": Compress to ~40% of original length. Retain main points and important supporting details.
- "detailed": Compress to ~70% of original length. Keep most details, simplify verbose passages.

RULES:
- Return exactly one transformed_text for each input segment_id.
- Do not merge, reorder, omit, or add segments.
- Preserve paragraph breaks using a single blank line.
- Maintain the author's tone and terminology.
- If a segment is very short (under 20 words), return it unchanged.`;

const CUSTOM_SYSTEM_PROMPT = `You are a text transformation engine for a reading app.
Output ONLY strict JSON in this format: {"segments":[{"segment_id":"...","transformed_text":"..."}]}.
No commentary, no markdown fences, no explanations.

GOAL: Apply the user's instructions to each input segment while preserving segment boundaries.

RULES:
- Return exactly one transformed_text for each input segment_id.
- Do not merge, reorder, omit, or add segments.
- Preserve paragraph breaks using a single blank line.
- Apply the transformation faithfully and consistently across all segments.`;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = (await req.json()) as TextTransformRequest;
    const segments = Array.isArray(body.segments) ? body.segments : [];

    if (!body.mode || !body.unit_id || segments.length === 0) {
      return jsonResponse({ error: "Invalid text-transform request" }, 400);
    }

    if (body.mode === "summarize" && !body.conciseness) {
      return jsonResponse({ error: "conciseness is required for summarize mode" }, 400);
    }

    if (body.mode === "custom" && !body.instructions?.trim()) {
      return jsonResponse({ error: "instructions is required for custom mode" }, 400);
    }

    const requestedModel = body.model?.trim() || Deno.env.get("TEXT_TRANSFORM_MODEL") || "gpt-4.1";
    const provider = resolveProvider(requestedModel);
    const model = resolveModelId(requestedModel, provider);

    let systemPrompt: string;
    let userContent: Record<string, unknown>;

    if (body.mode === "summarize") {
      systemPrompt = SUMMARIZE_SYSTEM_PROMPT;
      userContent = {
        conciseness: body.conciseness,
        unit_id: body.unit_id,
        unit_title: body.unit_title ?? null,
        segments: segments.map((s) => ({
          segment_id: s.id,
          text: s.text,
        })),
      };
    } else {
      systemPrompt = CUSTOM_SYSTEM_PROMPT;
      userContent = {
        instructions: body.instructions,
        unit_id: body.unit_id,
        unit_title: body.unit_title ?? null,
        segments: segments.map((s) => ({
          segment_id: s.id,
          text: s.text,
        })),
      };
    }

    const messages = [{ role: "user", content: JSON.stringify(userContent) }];

    const totalInputChars = segments.reduce((sum, s) => sum + s.text.length, 0);
    const maxTokens = Math.min(Math.max(Math.ceil(totalInputChars / 3) + 2048, 4096), 16384);

    const result = await callLLM(provider, systemPrompt, messages, model, undefined, maxTokens);
    const parsed = parseResponse(result.content);

    const response: { segments: TextTransformSegmentResponse[] } = {
      segments: segments.map((s) => ({
        segment_id: s.id,
        transformed_text: parsed.get(s.id) ?? s.text,
      })),
    };

    return jsonResponse(response, 200);
  } catch (error) {
    console.error("text-transform failed", error);
    return jsonResponse({ error: error instanceof Error ? error.message : "Unknown error" }, 500);
  }
});

function parseResponse(content: string): Map<string, string> {
  const cleaned = content
    .replace(/```json\n?/gi, "")
    .replace(/```\n?/g, "")
    .trim();

  const parsed = JSON.parse(cleaned) as {
    segments?: Array<{ segment_id?: string; transformed_text?: string }>;
  };
  const map = new Map<string, string>();

  for (const segment of parsed.segments ?? []) {
    if (segment.segment_id && typeof segment.transformed_text === "string") {
      map.set(segment.segment_id, segment.transformed_text);
    }
  }

  return map;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
