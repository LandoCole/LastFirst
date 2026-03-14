// curator-daily edge function — Scheduled daily curation generation
// Called by pg_cron. Returns immediately, runs generation in waitUntil.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { Finding } from "../_shared/types.ts";
import { callAnthropic } from "../_shared/llm.ts";
import { createSupabaseClient } from "../_shared/status.ts";
import { TOOL_DEFINITIONS, executeTool } from "../_shared/tools.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface DailyCurationConfig {
  id: string;
  user_id: string;
  enabled: boolean;
  generation_hour: number;
  max_items: number;
  last_generated_at: string | null;
}

function isToday(dateStr: string): boolean {
  const date = new Date(dateStr);
  const now = new Date();
  return (
    date.getUTCFullYear() === now.getUTCFullYear() &&
    date.getUTCMonth() === now.getUTCMonth() &&
    date.getUTCDate() === now.getUTCDate()
  );
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabase = createSupabaseClient();

  // Fetch eligible users
  const { data: configs } = await supabase
    .from("daily_curation_config")
    .select("*")
    .eq("enabled", true);

  const eligibleConfigs = (configs ?? []).filter(
    (c: DailyCurationConfig) => !c.last_generated_at || !isToday(c.last_generated_at)
  );

  // Return immediately
  // @ts-ignore: EdgeRuntime.waitUntil is available in Supabase Edge Functions
  EdgeRuntime.waitUntil(
    (async () => {
      for (const config of eligibleConfigs as DailyCurationConfig[]) {
        try {
          await generateDailyCuration(supabase, config);
          await supabase
            .from("daily_curation_config")
            .update({ last_generated_at: new Date().toISOString() })
            .eq("id", config.id);
        } catch (e) {
          console.error(`Daily curation failed for user ${config.user_id}:`, e);
        }
      }
    })()
  );

  return new Response(
    JSON.stringify({
      ok: true,
      eligible_users: eligibleConfigs.length,
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
});

// --- Daily Curation Generation ---

const DAILY_SYSTEM_PROMPT = `You are the Daily Curator for the LastFirst reading app. Your job is to create a personalized daily reading curation for a user based on their reading history and interests.

Analyze their reading patterns, then search for relevant content — prioritizing the internal library, supplemented by web discoveries. Create 3-5 high-quality recommendations with personalized notes.

After researching, respond with a JSON object:
{
  "title": "Short curation title (e.g. 'Your Thursday Reads')",
  "summary": "Brief narrative about today's picks and why they're relevant",
  "items": [
    {
      "content_id": "uuid or null",
      "external_url": "url or null",
      "external_title": "title",
      "external_author": "author",
      "external_summary": "summary",
      "agent_note": "personalized note",
      "item_type": "book|article|paper|content|external_link"
    }
  ]
}`;

async function generateDailyCuration(
  supabase: SupabaseClient,
  config: DailyCurationConfig
): Promise<void> {
  // Create the curation row
  const { data: curation } = await supabase
    .from("curations")
    .insert({
      user_id: config.user_id,
      type: "daily",
      title: "Daily Curation",
      status: "researching",
      complexity: "moderate",
      agent_count: 1,
      expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
    })
    .select("id")
    .single();

  if (!curation) throw new Error("Failed to create daily curation");
  const curationId = curation.id;

  // Build tools subset for daily curation
  const tools = TOOL_DEFINITIONS.filter((t) =>
    ["search_content", "search_web", "fetch_url", "get_user_reading_history", "get_content_details"].includes(t.name)
  );

  const messages: { role: string; content: unknown }[] = [
    {
      role: "user",
      content: `Create a daily curation for user ${config.user_id}. Find ${config.max_items} recommendations based on their reading history and current interests. Today is ${new Date().toLocaleDateString("en-US", { weekday: "long", year: "numeric", month: "long", day: "numeric" })}.`,
    },
  ];

  const maxIterations = 7;

  for (let i = 0; i < maxIterations; i++) {
    const result = await callAnthropic(
      DAILY_SYSTEM_PROMPT,
      messages,
      "claude-sonnet-4-20250514",
      tools,
      4096
    );

    if (result.toolCalls.length === 0) {
      // Parse final response and create items
      try {
        const cleaned = result.content.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
        const daily = JSON.parse(cleaned);

        // Update curation title and summary
        await supabase
          .from("curations")
          .update({
            title: daily.title ?? "Daily Curation",
            summary: daily.summary,
            status: "ready",
          })
          .eq("id", curationId);

        // Create items
        for (let j = 0; j < (daily.items ?? []).length; j++) {
          const item = daily.items[j];
          const insertData: Record<string, unknown> = {
            curation_id: curationId,
            item_type: item.item_type ?? "external_link",
            position: j,
            agent_note: item.agent_note,
          };

          if (item.content_id) insertData.content_id = item.content_id;
          if (item.external_url) insertData.external_url = item.external_url;
          if (item.external_title) insertData.external_title = item.external_title;
          if (item.external_author) insertData.external_author = item.external_author;
          if (item.external_summary) insertData.external_summary = item.external_summary;

          await supabase.from("curation_items").insert(insertData);
        }
      } catch {
        // Fallback: mark as ready with just the summary
        await supabase
          .from("curations")
          .update({ title: "Daily Curation", summary: result.content, status: "ready" })
          .eq("id", curationId);
      }
      return;
    }

    // Process tool calls
    messages.push({
      role: "assistant",
      content: result.toolCalls.length > 0
        ? [
            ...(result.content ? [{ type: "text", text: result.content }] : []),
            ...result.toolCalls.map((tc) => ({
              type: "tool_use",
              id: tc.id,
              name: tc.name,
              input: tc.input,
            })),
          ]
        : result.content,
    });

    for (const tc of result.toolCalls) {
      const toolResult = await executeTool(supabase, tc.name, tc.input, curationId);
      messages.push({
        role: "user",
        content: [
          {
            type: "tool_result",
            tool_use_id: tc.id,
            content: toolResult,
          },
        ],
      });
    }
  }

  // If we hit max iterations, mark as ready anyway
  await supabase
    .from("curations")
    .update({ status: "ready" })
    .eq("id", curationId);
}
