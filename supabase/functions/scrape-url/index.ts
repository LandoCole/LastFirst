import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FIRECRAWL_API_KEY = Deno.env.get("FIRECRAWL_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CACHE_BUCKET = "scrape-cache";

interface ScrapeRequest {
  url: string;
  formats?: string[];
}

interface ScrapeResult {
  title: string;
  content: string;
  markdown: string;
  textContent: string;
  byline: string | null;
  siteName: string | null;
  language: string | null;
  sourceUrl: string;
}

function extractAuthor(metadata: Record<string, unknown>): string {
  return String(
    metadata?.author ??
    metadata?.["og:author"] ??
    metadata?.["article:author"] ??
    metadata?.["dc.creator"] ??
    metadata?.["twitter:creator"] ??
    metadata?.ogAuthor ??
    ""
  );
}

async function hashURL(url: string): Promise<string> {
  const data = new TextEncoder().encode(url);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const { url, formats = ["markdown", "html"] } = (await req.json()) as ScrapeRequest;

    if (!url) {
      return new Response(JSON.stringify({ error: "url is required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Check cache
    const urlHash = await hashURL(url);
    const cachePath = `${urlHash}.json`;

    const { data: cached } = await supabase.storage
      .from(CACHE_BUCKET)
      .download(cachePath);

    if (cached) {
      const cachedResult = JSON.parse(await cached.text()) as ScrapeResult;
      return new Response(JSON.stringify(cachedResult), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // Call Firecrawl API
    const firecrawlResponse = await fetch("https://api.firecrawl.dev/v1/scrape", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${FIRECRAWL_API_KEY}`,
      },
      body: JSON.stringify({
        url,
        formats,
      }),
    });

    if (!firecrawlResponse.ok) {
      const errorBody = await firecrawlResponse.text();
      console.error("[scrape-url] Firecrawl error:", firecrawlResponse.status, errorBody);
      return new Response(
        JSON.stringify({ error: "Firecrawl scrape failed", details: errorBody }),
        { status: firecrawlResponse.status, headers: { "Content-Type": "application/json" } }
      );
    }

    const firecrawlData = await firecrawlResponse.json();
    const data = firecrawlData.data;
    const metadata = data.metadata ?? {};

    const result: ScrapeResult = {
      title: metadata.title ?? "",
      content: data.html ?? "",
      markdown: data.markdown ?? "",
      textContent: data.markdown?.replace(/[#*`\[\]()>_~|\\-]/g, "") ?? "",
      byline: extractAuthor(metadata) || null,
      siteName: metadata["og:site_name"] ?? metadata.ogSiteName ?? metadata.siteName ?? null,
      language: metadata.language ?? null,
      sourceUrl: url,
    };

    // Cache the result
    await supabase.storage
      .from(CACHE_BUCKET)
      .upload(cachePath, JSON.stringify(result), {
        contentType: "application/json",
        upsert: true,
      });

    return new Response(JSON.stringify(result), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("[scrape-url] Internal error:", error);
    return new Response(
      JSON.stringify({ error: "Internal error", details: String(error) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
