// Status emission utilities for curator edge functions

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { StatusMessage } from "./types.ts";

export function createSupabaseClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  return createClient(url, key);
}

export async function emitStatus(
  supabase: SupabaseClient,
  curationId: string,
  status: StatusMessage
): Promise<void> {
  await supabase.from("curation_messages").insert({
    curation_id: curationId,
    role: "tool",
    content: JSON.stringify(status),
  });
}

export function toolDisplayName(toolName: string): string {
  const names: Record<string, string> = {
    search_content: "Searching library",
    fetch_url: "Reading page",
    get_content_details: "Getting details",
    get_user_reading_history: "Reviewing reading history",
    create_curation_item: "Adding to curation",
    ingest_url: "Ingesting content",
  };
  return names[toolName] ?? toolName;
}

export function roleDisplayName(role: string): string {
  const names: Record<string, string> = {
    preference_analyst: "Preference Analyst",
    library_searcher: "Library Searcher",
    web_researcher: "Web Researcher",
  };
  return names[role] ?? role;
}
