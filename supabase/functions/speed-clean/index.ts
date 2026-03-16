import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { callLLM, resolveModelId, resolveProvider } from "../_shared/llm.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface SpeedCleanSegmentRequest {
  id: string;
  text: string;
  structural_kind?: string | null;
}

interface SpeedCleanRequest {
  profile: "book" | "article" | "pdfPaper";
  unit_id: string;
  unit_title?: string | null;
  segments: SpeedCleanSegmentRequest[];
  model?: string | null;
}

interface SpeedCleanSegmentResponse {
  segment_id: string;
  cleaned_text: string;
}

const SYSTEM_PROMPT = `You are a text cleaning engine for a word-by-word speed reading app.
Output ONLY strict JSON in this format: {"segments":[{"segment_id":"...","cleaned_text":"..."}]}.
No commentary, no markdown, no explanations.

GOAL: Transform each input segment into clean, linear, readable prose that flows naturally when displayed one word at a time.

REMOVE entirely:
- Footnotes, endnotes, and their reference markers like [1], ¹, and *
- Page numbers, headers, footers, and running titles
- Figure, table, and image captions and labels when they are not needed in the reading flow
- URLs, DOIs, citation blocks, and bibliography entries
- Anything that is metadata rather than content

REPLACE confirmed non-prose artifacts with one short placeholder:
- Tables -> "[ Table: <topic> ]"
- Images, figures, charts, and diagrams -> "[ Image: <topic> ]"
- Code blocks -> "[ Code: <language or purpose> ]"
- Complex math or formulas -> "[ Formula: <what it expresses> ]"

FIX silently:
- Missing spaces between words
- Broken hyphenation from line wrapping
- Inconsistent whitespace and line breaks
- OCR artifacts and garbled characters

PRESERVE exactly:
- The author's words, meaning, and sentence structure
- Paragraph breaks using a single blank line
- Proper nouns, terminology, and wording emphasis as plain text only

Return exactly one cleaned_text for each input segment_id.
Do not merge, reorder, omit, or explain segments.`;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = (await req.json()) as SpeedCleanRequest;
    const segments = Array.isArray(body.segments) ? body.segments : [];

    if (!body.profile || !body.unit_id || segments.length === 0) {
      return jsonResponse({ error: "Invalid speed-clean request" }, 400);
    }

    const deterministicResults = new Map<string, string>();
    const llmSegments: SpeedCleanSegmentRequest[] = [];

    for (const segment of segments) {
      const placeholder = artifactPlaceholder(segment);
      if (placeholder) {
        deterministicResults.set(segment.id, placeholder);
      } else {
        llmSegments.push(segment);
      }
    }

    if (llmSegments.length > 0) {
      const requestedModel = body.model?.trim() || Deno.env.get("SPEED_CLEAN_MODEL") || "gpt-4.1";
      const provider = resolveProvider(requestedModel);
      const model = resolveModelId(requestedModel, provider);
      const messages = [{
        role: "user",
        content: JSON.stringify({
          profile: body.profile,
          unit_id: body.unit_id,
          unit_title: body.unit_title ?? null,
          segments: llmSegments.map((segment) => ({
            segment_id: segment.id,
            text: segment.text,
            structural_kind: segment.structural_kind ?? null,
          })),
        }),
      }];

      const totalInputChars = llmSegments.reduce((sum, s) => sum + s.text.length, 0);
      const maxTokens = Math.min(Math.max(Math.ceil(totalInputChars / 3) + 2048, 4096), 16384);
      const result = await callLLM(provider, SYSTEM_PROMPT, messages, model, undefined, maxTokens);
      const parsed = parseResponse(result.content);

      for (const segment of llmSegments) {
        const cleaned = parsed.get(segment.id);
        if (cleaned && cleaned.trim().length > 0) {
          deterministicResults.set(segment.id, normalizeCleanedText(cleaned, segment));
        } else {
          deterministicResults.set(segment.id, fallbackText(segment.text));
        }
      }
    }

    const response: { segments: SpeedCleanSegmentResponse[] } = {
      segments: segments.map((segment) => ({
        segment_id: segment.id,
        cleaned_text: deterministicResults.get(segment.id) ?? fallbackText(segment.text),
      })),
    };

    return jsonResponse(response, 200);
  } catch (error) {
    console.error("speed-clean failed", error);
    return jsonResponse({ error: error instanceof Error ? error.message : "Unknown error" }, 500);
  }
});

function parseResponse(content: string): Map<string, string> {
  const cleaned = content
    .replace(/```json\n?/gi, "")
    .replace(/```\n?/g, "")
    .trim();

  const parsed = JSON.parse(cleaned) as { segments?: Array<{ segment_id?: string; cleaned_text?: string }> };
  const map = new Map<string, string>();

  for (const segment of parsed.segments ?? []) {
    if (segment.segment_id && typeof segment.cleaned_text === "string") {
      map.set(segment.segment_id, segment.cleaned_text);
    }
  }

  return map;
}

function artifactPlaceholder(segment: SpeedCleanSegmentRequest): string | null {
  if (segment.structural_kind === "codeBlock") {
    return artifactToken("Code", "code block");
  }

  const descriptor = artifactDescriptor(segment);
  if (!descriptor) {
    return null;
  }

  const kind = artifactTokenKind(descriptor, segment);
  const topic = artifactTokenTopic(descriptor, kind);
  return artifactToken(kind, topic);
}

function artifactDescriptor(segment: SpeedCleanSegmentRequest): { kindTitle: string; label?: string; descriptor?: string } | null {
  const trimmed = segment.text.trim();
  if (!trimmed) {
    return null;
  }

  const lines = trimmed
    .split(/\r?\n/)
    .map((line) => normalizeWhitespace(line))
    .filter(Boolean);
  const explicitMatch = trimmed.match(/^\s*(figure|fig\.|table|exhibit|chart|diagram)\s*([A-Za-z0-9.-]+)?\s*[:\-–]?\s*(.{0,120})/i);
  const symbolCount = Array.from(trimmed).filter((char) => "|\\/:;+-_=()[]{}".includes(char)).length;
  const tabularLineCount = lines.filter((line) => {
    return line.includes("|") ||
      line.includes("\t") ||
      /\S\s{2,}\S/.test(line) ||
      isNumericHeavyLine(line);
  }).length;
  const looksTabular = lines.length >= 2 && tabularLineCount >= 2;
  const looksLikeArtifact = Boolean(explicitMatch) || (looksTabular && symbolCount >= 8);

  if (!looksLikeArtifact) {
    return null;
  }

  if (explicitMatch) {
    const kindTitle = normalizeArtifactKind(explicitMatch[1] ?? "");
    const label = (explicitMatch[2] ?? "").trim();
    const descriptor = sanitizeArtifactDescriptor(explicitMatch[3] ?? "");
    return {
      kindTitle,
      label: label || undefined,
      descriptor: descriptor || undefined,
    };
  }

  const kindTitle = segment.structural_kind === "image" ? "Figure" : "Table";
  const descriptor = bestArtifactDescriptorLine(lines);
  return {
    kindTitle,
    descriptor: descriptor || undefined,
  };
}

function normalizeCleanedText(text: string, originalSegment: SpeedCleanSegmentRequest): string {
  const normalized = normalizeWhitespace(text);
  if (isArtifactPlaceholderText(normalized) && !artifactDescriptor(originalSegment)) {
    return fallbackText(originalSegment.text);
  }
  return normalized;
}

function fallbackText(text: string): string {
  return normalizeWhitespace(text).trim();
}

function normalizeWhitespace(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

function titleCase(text: string): string {
  if (!text) return text;
  return text.charAt(0).toUpperCase() + text.slice(1).toLowerCase();
}

function normalizeArtifactKind(text: string): string {
  const normalized = text.replace(/\./g, "").trim().toLowerCase();
  if (normalized === "fig") return "Figure";
  return titleCase(normalized);
}

function sanitizeArtifactDescriptor(text: string): string {
  const normalized = normalizeWhitespace(text).trim();
  if (!normalized) return "";
  const numberCount = Array.from(normalized).filter((char) => /\d/.test(char)).length;
  const letterCount = Array.from(normalized).filter((char) => /[a-z]/i.test(char)).length;
  if (letterCount < 3 && numberCount > 0) return "";
  return normalized.slice(0, 90).trim();
}

function bestArtifactDescriptorLine(lines: string[]): string {
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (trimmed.includes("|") || trimmed.includes("\t") || /\S\s{2,}\S/.test(trimmed)) continue;

    const descriptor = sanitizeArtifactDescriptor(trimmed);
    if (descriptor) {
      return descriptor;
    }
  }

  return "";
}

function artifactTokenKind(
  descriptor: { kindTitle: string; label?: string; descriptor?: string },
  segment: SpeedCleanSegmentRequest,
): string {
  switch (descriptor.kindTitle.toLowerCase()) {
    case "table":
      return "Table";
    case "figure":
    case "chart":
    case "diagram":
    case "exhibit":
      return "Image";
    default:
      if (segment.structural_kind === "image") {
        return "Image";
      }
      return "Table";
  }
}

function artifactTokenTopic(
  descriptor: { kindTitle: string; label?: string; descriptor?: string },
  kind: string,
): string {
  const candidates = [descriptor.label, descriptor.descriptor]
    .map((value) => value?.trim() ?? "")
    .filter(Boolean);

  if (candidates.length > 0) {
    return candidates.join(" ");
  }

  switch (kind) {
    case "Image":
      return "illustration";
    case "Code":
      return "code block";
    case "Formula":
      return "equation";
    default:
      return "data";
  }
}

function artifactToken(kind: string, topic: string): string {
  return `[ ${kind}: ${topic} ]`;
}

function isNumericHeavyLine(line: string): boolean {
  const numberCount = Array.from(line).filter((char) => /\d/.test(char)).length;
  const letterCount = Array.from(line).filter((char) => /[a-z]/i.test(char)).length;
  return numberCount >= 4 && numberCount >= Math.max(4, letterCount);
}

function isArtifactPlaceholderText(text: string): boolean {
  const lower = text.toLowerCase();
  return lower.includes("classic reader mode") ||
    lower.includes("document artifacts") ||
    /^\[\s*(table|image|code|formula)\s*:/i.test(text);
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
