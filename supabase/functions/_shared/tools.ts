// Shared tool execution for curator edge functions

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

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
    name: "search_web",
    description:
      "Search the web for books, articles, papers, or other reading material. Returns titles, URLs, and snippets.",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Search query" },
        num_results: { type: "number", description: "Number of results (default 5)" },
      },
      required: ["query"],
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
      "Ingest a URL into the content library using Firecrawl, making it available as a library item.",
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
      return TOOL_DEFINITIONS.filter((t) =>
        ["search_web", "fetch_url"].includes(t.name)
      );
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
    case "search_web":
      return await searchWeb(input);
    case "fetch_url":
      return await fetchUrl(input);
    case "get_user_reading_history":
      return await getUserReadingHistory(supabase, input);
    case "create_curation_item":
      return await createCurationItem(supabase, input);
    case "ingest_url":
      return await ingestUrl(input);
    default:
      return JSON.stringify({ error: `Unknown tool: ${toolName}` });
  }
}

// --- Tool Implementations ---

async function searchContent(
  supabase: SupabaseClient,
  input: Record<string, unknown>
): Promise<string> {
  const query = String(input.query ?? "");
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

async function searchWeb(input: Record<string, unknown>): Promise<string> {
  const query = String(input.query ?? "");
  const numResults = Number(input.num_results ?? 5);

  const serperKey = Deno.env.get("SERPER_API_KEY");
  if (!serperKey) return JSON.stringify({ error: "SERPER_API_KEY not set" });

  const res = await fetch("https://google.serper.dev/search", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-API-KEY": serperKey,
    },
    body: JSON.stringify({ q: query, num: numResults }),
  });

  if (!res.ok) {
    return JSON.stringify({ error: `Serper API error: ${res.status}` });
  }

  const data = await res.json();
  const results = (data.organic ?? []).map(
    (r: { title: string; link: string; snippet: string }) => ({
      title: r.title,
      url: r.link,
      snippet: r.snippet,
    })
  );

  return JSON.stringify({ results, count: results.length });
}

async function fetchUrl(input: Record<string, unknown>): Promise<string> {
  const url = String(input.url ?? "");

  // Use Firecrawl for extraction
  const firecrawlKey = Deno.env.get("FIRECRAWL_API_KEY");
  if (firecrawlKey) {
    try {
      const res = await fetch("https://api.firecrawl.dev/v1/scrape", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${firecrawlKey}`,
        },
        body: JSON.stringify({ url, formats: ["markdown"] }),
      });

      if (res.ok) {
        const data = await res.json();
        const doc = data.data ?? {};
        return JSON.stringify({
          title: doc.metadata?.title ?? "",
          author: doc.metadata?.author ?? "",
          content: (doc.markdown ?? "").slice(0, 3000),
          url,
        });
      }
    } catch {
      // Fall through to basic fetch
    }
  }

  // Basic fetch fallback
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": "LastFirst-Curator/1.0" },
    });
    const text = await res.text();
    // Extract title from HTML
    const titleMatch = text.match(/<title[^>]*>(.*?)<\/title>/i);
    return JSON.stringify({
      title: titleMatch?.[1]?.trim() ?? "",
      content: text.replace(/<[^>]*>/g, "").slice(0, 3000),
      url,
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

async function ingestUrl(input: Record<string, unknown>): Promise<string> {
  const url = String(input.url ?? "");
  const firecrawlKey = Deno.env.get("FIRECRAWL_API_KEY");
  if (!firecrawlKey) return JSON.stringify({ error: "FIRECRAWL_API_KEY not set" });

  try {
    const res = await fetch("https://api.firecrawl.dev/v1/scrape", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${firecrawlKey}`,
      },
      body: JSON.stringify({ url, formats: ["markdown", "html"] }),
    });

    if (!res.ok) {
      return JSON.stringify({ error: `Firecrawl error: ${res.status}` });
    }

    const data = await res.json();
    return JSON.stringify({
      success: true,
      title: data.data?.metadata?.title ?? input.title ?? "",
      author: data.data?.metadata?.author ?? input.author ?? "",
      content_preview: (data.data?.markdown ?? "").slice(0, 500),
      url,
    });
  } catch (e) {
    return JSON.stringify({ error: `Ingest failed: ${String(e)}` });
  }
}
