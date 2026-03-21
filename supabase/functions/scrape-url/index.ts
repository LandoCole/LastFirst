import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { DOMParser } from "https://deno.land/x/deno_dom@v0.1.48/deno-dom-wasm.ts";

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

function extractMetaContent(doc: ReturnType<DOMParser["parseFromString"]>, attrs: string[]): string {
  if (!doc) return "";
  for (const attr of attrs) {
    const el = doc.querySelector(`meta[name="${attr}"], meta[property="${attr}"]`);
    if (el) {
      const content = (el as unknown as Element).getAttribute("content");
      if (content) return content.trim();
    }
  }
  return "";
}

function htmlToMarkdown(html: string): string {
  let md = html;
  md = md.replace(/<h1[^>]*>([\s\S]*?)<\/h1>/gi, "# $1\n\n");
  md = md.replace(/<h2[^>]*>([\s\S]*?)<\/h2>/gi, "## $1\n\n");
  md = md.replace(/<h3[^>]*>([\s\S]*?)<\/h3>/gi, "### $1\n\n");
  md = md.replace(/<h4[^>]*>([\s\S]*?)<\/h4>/gi, "#### $1\n\n");
  md = md.replace(/<h5[^>]*>([\s\S]*?)<\/h5>/gi, "##### $1\n\n");
  md = md.replace(/<h6[^>]*>([\s\S]*?)<\/h6>/gi, "###### $1\n\n");
  md = md.replace(/<(strong|b)>([\s\S]*?)<\/(strong|b)>/gi, "**$2**");
  md = md.replace(/<(em|i)>([\s\S]*?)<\/(em|i)>/gi, "*$2*");
  md = md.replace(/<a[^>]+href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, "[$2]($1)");
  md = md.replace(/<p[^>]*>([\s\S]*?)<\/p>/gi, "$1\n\n");
  md = md.replace(/<br\s*\/?>/gi, "\n");
  md = md.replace(/<li[^>]*>([\s\S]*?)<\/li>/gi, "- $1\n");
  md = md.replace(/<blockquote[^>]*>([\s\S]*?)<\/blockquote>/gi, "> $1\n\n");
  md = md.replace(/<[^>]*>/g, "");
  md = md.replace(/\n{3,}/g, "\n\n").trim();
  md = md.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, " ");
  return md;
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
    const { url } = (await req.json()) as ScrapeRequest;

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

    // Fetch and parse with readability
    const fetchRes = await fetch(url, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; LastFirst/1.0)" },
      redirect: "follow",
    });

    if (!fetchRes.ok) {
      return new Response(
        JSON.stringify({ error: `Fetch failed: HTTP ${fetchRes.status}` }),
        { status: fetchRes.status, headers: { "Content-Type": "application/json" } }
      );
    }

    const html = await fetchRes.text();
    const doc = new DOMParser().parseFromString(html, "text/html");

    // Extract metadata
    const title = doc?.querySelector("title")?.textContent?.trim() ??
      extractMetaContent(doc, ["og:title", "twitter:title"]) ?? "";
    const byline = extractMetaContent(doc, [
      "author", "og:author", "article:author", "dc.creator", "twitter:creator",
    ]) || null;
    const siteName = extractMetaContent(doc, ["og:site_name"]) || null;
    const language = extractMetaContent(doc, ["language"]) ||
      (doc as unknown as { documentElement?: { getAttribute(n: string): string | null } })
        ?.documentElement?.getAttribute("lang") || null;

    // Extract main content
    const contentEl = doc?.querySelector("article") ??
      doc?.querySelector("main") ??
      doc?.querySelector("[role='main']") ??
      doc?.querySelector("body");

    if (contentEl) {
      for (const sel of ["script", "style", "nav", "header", "footer", "aside", "iframe", "noscript", "svg"]) {
        for (const el of contentEl.querySelectorAll(sel)) {
          el.remove();
        }
      }
    }

    const contentHtml = contentEl?.innerHTML ?? "";
    const markdown = htmlToMarkdown(contentHtml);
    const textContent = markdown.replace(/[#*`\[\]()>_~|\\-]/g, "");

    const result: ScrapeResult = {
      title,
      content: contentHtml,
      markdown,
      textContent,
      byline,
      siteName,
      language,
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
