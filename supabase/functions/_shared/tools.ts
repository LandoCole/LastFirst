// Shared tool execution for curator edge functions

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { DOMParser } from "https://deno.land/x/deno_dom@v0.1.48/deno-dom-wasm.ts";

// --- Tool Definitions ---

export const TOOL_DEFINITIONS = [
  {
    name: "search_content",
    description:
      "Search the internal content library for books, articles, and papers. Returns titles, authors, summaries, and IDs.",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Search query" },
        limit: { type: "number", description: "Max results (default 10)" },
      },
      required: ["query"],
    },
  },
  {
    name: "get_content_details",
    description:
      "Get full details for a specific content item by ID, including summary, file type, and availability.",
    input_schema: {
      type: "object",
      properties: {
        content_id: { type: "string", description: "UUID of the content item" },
      },
      required: ["content_id"],
    },
  },
  {
    name: "fetch_url",
    description:
      "Fetch and extract content from a URL. Returns title, author, and text content.",
    input_schema: {
      type: "object",
      properties: {
        url: { type: "string", description: "URL to fetch" },
      },
      required: ["url"],
    },
  },
  {
    name: "get_user_reading_history",
    description:
      "Get the user's reading history including past interactions, bookmarks, and reading sessions.",
    input_schema: {
      type: "object",
      properties: {
        user_id: { type: "string", description: "User UUID" },
        limit: { type: "number", description: "Max results (default 20)" },
      },
      required: ["user_id"],
    },
  },
  {
    name: "create_curation_item",
    description:
      "Add an item to the current curation. Can be internal content or an external link.",
    input_schema: {
      type: "object",
      properties: {
        curation_id: { type: "string", description: "Curation UUID" },
        content_id: { type: "string", description: "Content UUID (for library items)" },
        external_url: { type: "string", description: "External URL (for web items)" },
        external_title: { type: "string", description: "Title for external items" },
        external_author: { type: "string", description: "Author for external items" },
        external_summary: { type: "string", description: "Summary for external items" },
        agent_note: {
          type: "string",
          description: "Curator's personalized note about why this item is recommended",
        },
        item_type: {
          type: "string",
          enum: ["content", "external_link", "book", "article", "paper", "pdf"],
          description: "Type of item",
        },
      },
      required: ["curation_id", "item_type"],
    },
  },
  {
    name: "ingest_url",
    description:
      "Ingest a URL into the content library, making it available as a library item.",
    input_schema: {
      type: "object",
      properties: {
        url: { type: "string", description: "URL to ingest" },
        title: { type: "string", description: "Title override" },
        author: { type: "string", description: "Author override" },
      },
      required: ["url"],
    },
  },
];

// Subsets for different agent roles
export function getSubagentTools(role: string) {
  switch (role) {
    case "preference_analyst":
      return TOOL_DEFINITIONS.filter((t) => t.name === "get_user_reading_history");
    case "library_searcher":
      return TOOL_DEFINITIONS.filter((t) =>
        ["search_content", "get_content_details"].includes(t.name)
      );
    case "web_researcher":
      return TOOL_DEFINITIONS.filter((t) => t.name === "fetch_url");
    default:
      return TOOL_DEFINITIONS;
  }
}

export function getMaxIterations(role: string): number {
  switch (role) {
    case "preference_analyst":
      return 3;
    case "library_searcher":
      return 5;
    case "web_researcher":
      return 7;
    default:
      return 5;
  }
}

// --- Tool Execution ---

export async function executeTool(
  supabase: SupabaseClient,
  toolName: string,
  input: Record<string, unknown>,
  _curationId: string
): Promise<string> {
  switch (toolName) {
    case "search_content":
      return await searchContent(supabase, input);
    case "get_content_details":
      return await getContentDetails(supabase, input);
    case "fetch_url":
      return await fetchUrl(input);
    case "get_user_reading_history":
      return await getUserReadingHistory(supabase, input);
    case "create_curation_item":
      return await createCurationItem(supabase, input);
    case "ingest_url":
      return await ingestUrl(supabase, input);
    default:
      return JSON.stringify({ error: `Unknown tool: ${toolName}` });
  }
}

// --- Helpers ---

function sanitizePostgrestValue(value: string): string {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/%/g, "\\%")
    .replace(/\./g, "\\.")
    .replace(/,/g, "\\,")
    .replace(/\(/g, "\\(")
    .replace(/\)/g, "\\)");
}

// --- Scraping Helpers ---

interface ScrapeOutput {
  title: string;
  author: string;
  markdown: string;
  html: string;
  metadata: Record<string, string>;
}

async function scrapeUrl(url: string): Promise<ScrapeOutput> {
  const res = await fetch(url, {
    headers: { "User-Agent": "Mozilla/5.0 (compatible; LastFirst/1.0)" },
    redirect: "follow",
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const html = await res.text();

  const doc = new DOMParser().parseFromString(html, "text/html");
  if (!doc) throw new Error("Failed to parse HTML");

  // Extract metadata from <meta> tags
  const metadata: Record<string, string> = {};
  for (const meta of doc.querySelectorAll("meta")) {
    const name = (meta as unknown as Element).getAttribute("name") ??
      (meta as unknown as Element).getAttribute("property") ?? "";
    const content = (meta as unknown as Element).getAttribute("content") ?? "";
    if (name && content) metadata[name] = content;
  }

  // Extract title
  const title = doc.querySelector("title")?.textContent?.trim() ??
    metadata["og:title"] ?? metadata["twitter:title"] ?? "";

  // Extract author
  const author = metadata["author"] ?? metadata["og:author"] ??
    metadata["article:author"] ?? metadata["dc.creator"] ??
    metadata["twitter:creator"] ?? "";

  // Simple readability: extract main content element
  const contentEl = doc.querySelector("article") ??
    doc.querySelector("main") ??
    doc.querySelector("[role='main']") ??
    doc.querySelector("body");

  // Remove unwanted elements
  if (contentEl) {
    const removeSelectors = [
      "script", "style", "nav", "header", "footer", "aside",
      "iframe", "noscript", "svg",
    ];
    for (const sel of removeSelectors) {
      for (const el of contentEl.querySelectorAll(sel)) {
        el.remove();
      }
    }
  }

  const contentHtml = contentEl?.innerHTML ?? "";
  const markdown = htmlToMarkdown(contentHtml);

  return { title, author, markdown, html: contentHtml, metadata };
}

function htmlToMarkdown(html: string): string {
  let md = html;
  // Convert headings
  md = md.replace(/<h1[^>]*>([\s\S]*?)<\/h1>/gi, "# $1\n\n");
  md = md.replace(/<h2[^>]*>([\s\S]*?)<\/h2>/gi, "## $1\n\n");
  md = md.replace(/<h3[^>]*>([\s\S]*?)<\/h3>/gi, "### $1\n\n");
  md = md.replace(/<h4[^>]*>([\s\S]*?)<\/h4>/gi, "#### $1\n\n");
  md = md.replace(/<h5[^>]*>([\s\S]*?)<\/h5>/gi, "##### $1\n\n");
  md = md.replace(/<h6[^>]*>([\s\S]*?)<\/h6>/gi, "###### $1\n\n");
  // Convert bold and italic
  md = md.replace(/<(strong|b)>([\s\S]*?)<\/(strong|b)>/gi, "**$2**");
  md = md.replace(/<(em|i)>([\s\S]*?)<\/(em|i)>/gi, "*$2*");
  // Convert links
  md = md.replace(/<a[^>]+href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, "[$2]($1)");
  // Convert paragraphs
  md = md.replace(/<p[^>]*>([\s\S]*?)<\/p>/gi, "$1\n\n");
  // Convert line breaks
  md = md.replace(/<br\s*\/?>/gi, "\n");
  // Convert list items
  md = md.replace(/<li[^>]*>([\s\S]*?)<\/li>/gi, "- $1\n");
  // Convert blockquotes
  md = md.replace(/<blockquote[^>]*>([\s\S]*?)<\/blockquote>/gi, "> $1\n\n");
  // Strip remaining tags
  md = md.replace(/<[^>]*>/g, "");
  // Clean up whitespace
  md = md.replace(/\n{3,}/g, "\n\n").trim();
  // Decode HTML entities
  md = md.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, " ");
  return md;
}

// --- Tool Implementations ---

async function searchContent(
  supabase: SupabaseClient,
  input: Record<string, unknown>
): Promise<string> {
  const query = sanitizePostgrestValue(String(input.query ?? ""));
  const limit = Number(input.limit ?? 10);

  const { data, error } = await supabase
    .from("content")
    .select("id, title, author, summary, file_type, is_available")
    .or(`title.ilike.%${query}%,author.ilike.%${query}%,summary.ilike.%${query}%`)
    .eq("is_available", true)
    .limit(limit);

  if (error) return JSON.stringify({ error: error.message });
  return JSON.stringify({ results: data ?? [], count: data?.length ?? 0 });
}

async function getContentDetails(
  supabase: SupabaseClient,
  input: Record<string, unknown>
): Promise<string> {
  const contentId = String(input.content_id ?? "");

  const { data, error } = await supabase
    .from("content")
    .select("*")
    .eq("id", contentId)
    .single();

  if (error) return JSON.stringify({ error: error.message });
  return JSON.stringify(data);
}

async function fetchUrl(input: Record<string, unknown>): Promise<string> {
  const url = String(input.url ?? "");

  try {
    const scraped = await scrapeUrl(url);
    return JSON.stringify({
      title: scraped.title,
      author: scraped.author,
      content: scraped.markdown.slice(0, 4000),
      url,
      readable: scraped.markdown.length > 200,
    });
  } catch (e) {
    return JSON.stringify({ error: `Failed to fetch: ${String(e)}` });
  }
}

async function getUserReadingHistory(
  supabase: SupabaseClient,
  input: Record<string, unknown>
): Promise<string> {
  const userId = String(input.user_id ?? "");
  const limit = Number(input.limit ?? 20);

  // Fetch interactions
  const { data: interactions } = await supabase
    .from("interactions")
    .select("kind, content:content_id(id, title, author, file_type), created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(limit);

  // Fetch recent reading sessions
  const { data: sessions } = await supabase
    .from("reading_sessions")
    .select("content_id, duration_seconds, pages_read, started_at")
    .eq("user_id", userId)
    .order("started_at", { ascending: false })
    .limit(limit);

  // Fetch past curations
  const { data: curations } = await supabase
    .from("curations")
    .select("id, title, prompt, status, created_at")
    .eq("user_id", userId)
    .eq("status", "ready")
    .order("created_at", { ascending: false })
    .limit(5);

  return JSON.stringify({
    interactions: interactions ?? [],
    reading_sessions: sessions ?? [],
    past_curations: curations ?? [],
  });
}

async function createCurationItem(
  supabase: SupabaseClient,
  input: Record<string, unknown>
): Promise<string> {
  // Get current max position
  const { data: existing } = await supabase
    .from("curation_items")
    .select("position")
    .eq("curation_id", String(input.curation_id))
    .order("position", { ascending: false })
    .limit(1);

  const nextPosition = (existing?.[0]?.position ?? -1) + 1;

  const item: Record<string, unknown> = {
    curation_id: input.curation_id,
    item_type: input.item_type ?? "content",
    position: nextPosition,
  };

  if (input.content_id) item.content_id = input.content_id;
  if (input.external_url) item.external_url = input.external_url;
  if (input.external_title) item.external_title = input.external_title;
  if (input.external_author) item.external_author = input.external_author;
  if (input.external_summary) item.external_summary = input.external_summary;
  if (input.agent_note) item.agent_note = input.agent_note;

  const { data, error } = await supabase
    .from("curation_items")
    .insert(item)
    .select("id")
    .single();

  if (error) return JSON.stringify({ error: error.message });
  return JSON.stringify({ success: true, item_id: data.id, position: nextPosition });
}

async function ingestUrl(
  supabase: SupabaseClient,
  input: Record<string, unknown>
): Promise<string> {
  const url = String(input.url ?? "");

  try {
    const scraped = await scrapeUrl(url);
    const title = String(input.title ?? "") || scraped.title;
    const author = String(input.author ?? "") || scraped.author;
    const wordCount = scraped.markdown.split(/\s+/).filter(Boolean).length;
    const estimatedReadMinutes = Math.max(1, Math.round(wordCount / 238));

    // Persist to content table
    let contentId: string | null = null;
    try {
      const { data: upserted, error: upsertError } = await supabase
        .from("content")
        .upsert(
          {
            source_type: "web",
            source_url: url,
            title,
            author: author || null,
            summary: scraped.markdown.slice(0, 500),
            body_text: scraped.markdown,
            body_html: scraped.html,
            language: scraped.metadata["language"] ?? scraped.metadata["og:locale"] ?? "en",
            word_count: wordCount,
            estimated_read_minutes: estimatedReadMinutes,
            file_type: "web",
            is_available: true,
            metadata: scraped.metadata,
          },
          { onConflict: "source_url" }
        )
        .select("id")
        .single();

      if (upsertError) {
        console.error("[ingestUrl] Upsert failed:", upsertError.message);
      } else {
        contentId = upserted.id;
      }
    } catch (dbError) {
      console.error("[ingestUrl] DB error:", dbError);
    }

    return JSON.stringify({
      success: true,
      content_id: contentId,
      title,
      author,
      content_preview: scraped.markdown.slice(0, 500),
      url,
    });
  } catch (e) {
    console.error("[ingestUrl] Ingest failed:", e);
    return JSON.stringify({ error: `Ingest failed: ${String(e)}` });
  }
}
