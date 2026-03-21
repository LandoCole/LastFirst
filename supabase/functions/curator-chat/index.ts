// curator-chat edge function — Multi-Agent Orchestrator
// Handles SIMPLE queries inline, MODERATE/COMPLEX via waitUntil with parallel subagents

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type {
  CuratorRequest,
  NormalizedLLMResponse,
  Finding,
  SubagentConfig,
  SubagentResult,
  ClassificationResult,
} from "../_shared/types.ts";
import {
  callAnthropic,
  callLLM,
  resolveProvider,
  resolveModelId,
} from "../_shared/llm.ts";
import { emitStatus, toolDisplayName, roleDisplayName, createSupabaseClient } from "../_shared/status.ts";
import {
  TOOL_DEFINITIONS,
  getSubagentTools,
  getMaxIterations,
  executeTool,
} from "../_shared/tools.ts";

declare const Deno: {
  env: {
    get(name: string): string | undefined;
  };
};

// --- CORS ---
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

class HttpError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
    this.name = "HttpError";
  }
}

// --- External Agent Service Delegation ---

function getAgentServiceConfig(): { url: string; internalKey: string } | null {
  const url = Deno.env.get("AGENT_SERVICE_URL");
  const internalKey = Deno.env.get("AGENT_SERVICE_INTERNAL_KEY");
  if (!url || !internalKey) {
    return null;
  }
  return { url: url.replace(/\/$/, ""), internalKey };
}

async function invokeExternalCuratorChat(
  req: Request,
  body: CuratorRequest,
  userId: string
): Promise<Response | null> {
  const config = getAgentServiceConfig();
  if (!config) {
    return null;
  }

  const payload = { ...body, user_id: userId };
  const response = await fetch(`${config.url}/internal/curator-chat`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Agent-Service-Key": config.internalKey,
    },
    body: JSON.stringify(payload),
  });

  const responseText = await response.text();
  if (!response.ok) {
    console.error("External curator-chat error:", response.status, responseText);
    return new Response(
      JSON.stringify({ error: "External curator-chat failed", details: responseText }),
      {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  let result: Record<string, unknown>;
  try {
    result = JSON.parse(responseText) as Record<string, unknown>;
  } catch {
    result = { raw: responseText };
  }

  return new Response(JSON.stringify(result), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function createRequestScopedSupabaseClient(req: Request): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const authHeader = req.headers.get("Authorization");

  if (!url || !anonKey) {
    throw new HttpError(500, "Supabase auth environment is not configured");
  }

  if (!authHeader) {
    throw new HttpError(401, "Curator requires a signed-in session");
  }

  return createClient(url, anonKey, {
    global: {
      headers: {
        Authorization: authHeader,
      },
    },
  });
}

async function getAuthenticatedUserId(req: Request): Promise<string> {
  const authClient = createRequestScopedSupabaseClient(req);
  const { data, error } = await authClient.auth.getUser();

  if (error || !data.user) {
    throw new HttpError(401, "Curator requires a valid signed-in session");
  }

  return data.user.id;
}

// --- System Prompts ---

const CURATOR_SYSTEM_PROMPT = `You are the Curator, an AI research agent for the LastFirst reading app. Your job is to help users discover books, articles, papers, and other reading material.

You have access to tools to search the internal library, fetch URLs, and add items to curations. You also have built-in web search capability for finding content online. Use multiple search strategies to find the best results.

When you find relevant content, use create_curation_item to add it to the curation with a personalized agent_note explaining why you're recommending it.

Be conversational but efficient. Always search before recommending. Prefer library content when available, supplement with web finds.`;

const CLASSIFIER_PROMPT = `You classify user queries for a reading curation agent. Respond with ONLY valid JSON.

Categories:
- SIMPLE: Direct lookup or single known item. "Find The Art of War", "Do we have any Hemingway?"
- MODERATE: Topic-based search, single domain. "Find me articles about stoicism", "Recommend philosophy books"
- COMPLEX: Multi-topic, cross-domain, research-intensive. "Research the intersection of AI and philosophy — books, papers, and articles"

For MODERATE/COMPLEX, decompose into focused subqueries with roles:
- library_searcher: searches internal content catalog
- web_researcher: finds external content on the web

Response format:
{"complexity":"simple|moderate|complex","subqueries":[{"role":"library_searcher|web_researcher","query":"focused query"}],"reasoning":"brief explanation"}`;

function getSubagentPrompt(role: string, userPreferences?: Finding[]): string {
  const prefContext = userPreferences?.length
    ? `\n\nUser preference context (from reading history analysis):\n${JSON.stringify(userPreferences, null, 2)}`
    : "";

  switch (role) {
    case "preference_analyst":
      return `You analyze a user's reading history to infer their interests, preferences, and reading patterns. Examine their interactions, reading sessions, and past curations. Return structured findings about their preferences as a JSON array of findings.

Each finding should be: {"source":"library","title":"Preference insight","relevance_note":"description of the pattern","confidence":0.8}

Focus on: genres they gravitate toward, authors they follow, topics of interest, reading frequency patterns, content types they prefer.`;

    case "library_searcher":
      return `You are a Library Searcher agent for the LastFirst reading app. Search the internal content library thoroughly using multiple query variations to find relevant items.${prefContext}

For each relevant item found, include it in your findings. Try at least 2-3 different search queries to maximize coverage. Return findings as a JSON array.

Each finding: {"source":"library","content_id":"uuid","title":"...","author":"...","summary":"...","relevance_note":"why this is relevant","confidence":0.0-1.0}`;

    case "web_researcher":
      return `You are a Web Researcher agent for the LastFirst reading app. You have built-in web search capability to find books, articles, papers, and reading material that aren't in the internal library.${prefContext}

Use multiple search queries with different angles. For promising results, use the fetch_url tool to get more details. Return findings as a JSON array.

Each finding: {"source":"web","url":"...","title":"...","author":"...","summary":"...","relevance_note":"why this is relevant","confidence":0.0-1.0}`;

    default:
      return CURATOR_SYSTEM_PROMPT;
  }
}

// --- Main Handler ---

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = (await req.json()) as CuratorRequest;
    const authenticatedUserId = await getAuthenticatedUserId(req);
    const message = body.message?.trim();

    if (!message) {
      throw new HttpError(400, "Message is required");
    }

    if (body.user_id && body.user_id !== authenticatedUserId) {
      throw new HttpError(403, "Authenticated user does not match the curator request");
    }

    // Delegate to Railway agent service if configured
    const delegatedResponse = await invokeExternalCuratorChat(
      req,
      { ...body, message },
      authenticatedUserId
    );
    if (delegatedResponse) {
      return delegatedResponse;
    }

    const request: CuratorRequest = {
      ...body,
      message,
      user_id: authenticatedUserId,
    };
    const supabase = createSupabaseClient();

    // Get or create curation
    const curationId = await getOrCreateCuration(supabase, request, authenticatedUserId);
    await saveUserMessage(supabase, curationId, request.message);

    // Fetch conversation history for context
    const history = await getConversationHistory(supabase, curationId);

    // Classify complexity
    const classification = await classifyQuery(request.message, history);
    const totalAgentCount = classification.complexity === "simple" ? 1 : classification.subqueries.length + 1;

    // Update curation with complexity
    await supabase
      .from("curations")
      .update({
        complexity: classification.complexity,
        agent_count: totalAgentCount,
      })
      .eq("id", curationId);

    if (classification.complexity === "simple") {
      // SIMPLE: inline agentic loop (backward compatible)
      const result = await runInlineAgentLoop(supabase, curationId, request, history);

      // Save assistant message
      await supabase.from("curation_messages").insert({
        curation_id: curationId,
        role: "assistant",
        content: result.response,
      });

      await supabase
        .from("curations")
        .update({ status: "ready" })
        .eq("id", curationId);

      return new Response(
        JSON.stringify({
          curation_id: curationId,
          response: result.response,
          items_added: result.itemsAdded,
          complexity: classification.complexity,
          agent_count: totalAgentCount,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // MODERATE/COMPLEX: return immediately, run in background
    await emitStatus(supabase, curationId, {
      type: "agent_spawned",
      totalAgents: totalAgentCount,
      message: `Launching ${totalAgentCount} research agents...`,
    });

    // @ts-ignore: EdgeRuntime.waitUntil is available in Supabase Edge Functions
    EdgeRuntime.waitUntil(
      (async () => {
        try {
          await supabase
            .from("curations")
            .update({ status: "researching" })
            .eq("id", curationId);

          // 1. Run preference analyst first
          const userPrefs = await runSubagent(supabase, curationId, {
            role: "preference_analyst",
            query: "Analyze user reading history and preferences",
            userId: request.user_id!,
          });

          // 2. Run remaining subagents in parallel
          const subagentResults = await Promise.all(
            classification.subqueries.map((sq) =>
              runSubagent(supabase, curationId, {
                role: sq.role,
                query: sq.query,
                userId: request.user_id!,
                userPreferences: userPrefs.findings,
              })
            )
          );

          // 3. Synthesize findings
          const allFindings = subagentResults.flatMap((r) => r.findings);
          await synthesizeAndCreateItems(supabase, curationId, allFindings, request, history);

          // 4. Mark ready
          await supabase
            .from("curations")
            .update({ status: "ready", complexity: classification.complexity })
            .eq("id", curationId);
        } catch (error) {
          console.error("Multi-agent orchestration error:", error);
          await supabase
            .from("curations")
            .update({
              status: "error",
              error_message: String(error),
            })
            .eq("id", curationId);

          await emitStatus(supabase, curationId, {
            type: "error",
            message: `Research failed: ${String(error)}`,
          });
        }
      })()
    );

    return new Response(
      JSON.stringify({
        curation_id: curationId,
        complexity: classification.complexity,
        agent_count: totalAgentCount,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Curator chat error:", error);
    const status = error instanceof HttpError ? error.status : 500;
    const message = error instanceof Error ? error.message : String(error);
    return new Response(
      JSON.stringify({ error: message }),
      { status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

// --- Curation Management ---

async function getOrCreateCuration(
  supabase: SupabaseClient,
  body: CuratorRequest,
  userId: string
): Promise<string> {
  if (body.curation_id) {
    const { data, error } = await supabase
      .from("curations")
      .select("id, user_id")
      .eq("id", body.curation_id)
      .single();

    if (error || !data) {
      throw new HttpError(404, "Curation not found");
    }

    if (data.user_id !== userId) {
      throw new HttpError(403, "You do not have access to this curation");
    }

    return data.id;
  }

  const { data, error } = await supabase
    .from("curations")
    .insert({
      user_id: userId,
      type: "user_directed",
      title: body.message.slice(0, 100),
      prompt: body.message,
      status: "researching",
    })
    .select("id")
    .single();

  if (error) throw new Error(`Failed to create curation: ${error.message}`);
  return data.id;
}

async function saveUserMessage(
  supabase: SupabaseClient,
  curationId: string,
  message: string
): Promise<void> {
  await supabase.from("curation_messages").insert({
    curation_id: curationId,
    role: "user",
    content: message,
  });
}

async function getConversationHistory(
  supabase: SupabaseClient,
  curationId: string
): Promise<{ role: string; content: string }[]> {
  const { data } = await supabase
    .from("curation_messages")
    .select("role, content")
    .eq("curation_id", curationId)
    .in("role", ["user", "assistant"])
    .order("created_at", { ascending: true });

  return (data ?? []).map((m: { role: string; content: string }) => ({
    role: m.role,
    content: m.content,
  }));
}

// --- Complexity Classifier ---

async function classifyQuery(
  message: string,
  history: { role: string; content: string }[]
): Promise<ClassificationResult> {
  const contextSummary =
    history.length > 1
      ? `\n\nConversation context (${history.length} messages):\n${history
          .slice(-4)
          .map((m) => `${m.role}: ${m.content.slice(0, 200)}`)
          .join("\n")}`
      : "";

  try {
    const result = await callAnthropic(
      CLASSIFIER_PROMPT,
      [{ role: "user", content: `Classify this query:${contextSummary}\n\nUser query: "${message}"` }],
      "claude-haiku-4-5-20251001",
      undefined,
      512
    );

    const parsed = JSON.parse(result.content.trim());
    return {
      complexity: parsed.complexity ?? "simple",
      subqueries: parsed.subqueries ?? [],
      reasoning: parsed.reasoning ?? "",
    };
  } catch (e) {
    console.error("Classification failed, defaulting to simple:", e);
    return { complexity: "simple", subqueries: [], reasoning: "Classification failed" };
  }
}

// --- Inline Agent Loop (SIMPLE queries) ---

async function runInlineAgentLoop(
  supabase: SupabaseClient,
  curationId: string,
  body: CuratorRequest,
  history: { role: string; content: string }[]
): Promise<{ response: string; itemsAdded: number }> {
  const provider = resolveProvider(body.model ?? "claude");
  const modelId = resolveModelId(body.model ?? "claude", provider);
  const stepStartMessages = [
    "Searching for relevant content...",
    "Reviewing promising matches...",
    "Adding recommendations to your curation...",
  ];
  const stepCompleteMessages = [
    "Search complete",
    "Evaluation complete",
    "Curation complete",
  ];

  // Build plan
  await emitStatus(supabase, curationId, {
    type: "plan",
    plan: [
      { label: "Search", description: "Looking for relevant content" },
      { label: "Evaluate", description: "Reviewing and selecting the best matches" },
      { label: "Curate", description: "Adding items with personalized notes" },
    ],
  });

  const messages: { role: string; content: unknown }[] = history.map((m) => ({
    role: m.role,
    content: m.content,
  }));

  let itemsAdded = 0;
  const maxIterations = 10;
  let activeStepIndex: number | null = null;
  const completedSteps = new Set<number>();

  for (let i = 0; i < maxIterations; i++) {
    const result = await callLLM(
      provider,
      CURATOR_SYSTEM_PROMPT,
      messages,
      modelId,
      TOOL_DEFINITIONS,
      4096,
      true
    );

    if (result.toolCalls.length === 0) {
      if (activeStepIndex !== null && !completedSteps.has(activeStepIndex)) {
        await emitStatus(supabase, curationId, {
          type: "step_complete",
          stepIndex: activeStepIndex,
          message: stepCompleteMessages[activeStepIndex] ?? "Step complete",
        });
      }
      return { response: result.content, itemsAdded };
    }

    // Process tool calls
    messages.push({
      role: "assistant",
      content: formatAssistantContent(result),
    });

    for (const tc of result.toolCalls) {
      const stepIndex = tc.name === "search_content" ? 0
        : tc.name === "get_content_details" || tc.name === "fetch_url" ? 1 : 2;

      if (activeStepIndex !== stepIndex) {
        if (activeStepIndex !== null && !completedSteps.has(activeStepIndex)) {
          await emitStatus(supabase, curationId, {
            type: "step_complete",
            stepIndex: activeStepIndex,
            message: stepCompleteMessages[activeStepIndex] ?? "Step complete",
          });
          completedSteps.add(activeStepIndex);
        }

        if (!completedSteps.has(stepIndex)) {
          await emitStatus(supabase, curationId, {
            type: "step_start",
            stepIndex,
            message: stepStartMessages[stepIndex] ?? "Working...",
          });
        }

        activeStepIndex = stepIndex;
      }

      await emitStatus(supabase, curationId, {
        type: "step_progress",
        stepIndex,
        tool: tc.name,
        message: toolDisplayName(tc.name),
      });

      const toolResult = await executeTool(supabase, tc.name, tc.input, curationId);

      if (tc.name === "create_curation_item") {
        itemsAdded++;
        await emitStatus(supabase, curationId, {
          type: "finding",
          stepIndex: 2,
          finding: `Added: ${(tc.input as Record<string, string>).external_title ?? "library item"}`,
        });
      }

      // Format tool result for the provider
      if (provider === "anthropic") {
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
      } else if (provider === "openai") {
        messages.push({
          role: "tool",
          tool_call_id: tc.id,
          content: toolResult,
        } as unknown as { role: string; content: unknown });
      } else {
        // Gemini: function response format
        messages.push({
          role: "user",
          content: [
            {
              type: "function_response",
              name: tc.name,
              response: { content: toolResult },
            },
          ],
        });
      }
    }
  }

  if (activeStepIndex !== null && !completedSteps.has(activeStepIndex)) {
    await emitStatus(supabase, curationId, {
      type: "step_complete",
      stepIndex: activeStepIndex,
      message: stepCompleteMessages[activeStepIndex] ?? "Step complete",
    });
  }

  return { response: "I've finished researching. Check the curated items above!", itemsAdded };
}

function formatAssistantContent(result: NormalizedLLMResponse): unknown {
  if (result.rawContent) {
    return result.rawContent;
  }
  const blocks: unknown[] = [];
  if (result.content) {
    blocks.push({ type: "text", text: result.content });
  }
  for (const tc of result.toolCalls) {
    blocks.push({ type: "tool_use", id: tc.id, name: tc.name, input: tc.input });
  }
  return blocks;
}

// --- Subagent Runner ---

async function runSubagent(
  supabase: SupabaseClient,
  curationId: string,
  config: SubagentConfig
): Promise<SubagentResult> {
  const systemPrompt = getSubagentPrompt(config.role, config.userPreferences);
  const tools = getSubagentTools(config.role);
  const maxIter = getMaxIterations(config.role);

  // Record task for observability
  const { data: task } = await supabase
    .from("agent_tasks")
    .insert({
      curation_id: curationId,
      agent_role: config.role,
      query: config.query,
      status: "running",
      started_at: new Date().toISOString(),
    })
    .select("id")
    .single();

  const taskId = task?.id ?? crypto.randomUUID();

  await emitStatus(supabase, curationId, {
    type: "agent_progress",
    agentRole: config.role,
    agentTaskId: taskId,
    message: `${roleDisplayName(config.role)}: starting...`,
  });

  const messages: { role: string; content: unknown }[] = [
    { role: "user", content: config.query },
  ];

  const findings: Finding[] = [];
  let totalTokens = 0;

  try {
    for (let i = 0; i < maxIter; i++) {
      const result = await callAnthropic(
        systemPrompt,
        messages,
        "claude-sonnet-4-20250514",
        tools.length > 0 ? tools : undefined,
        4096,
        config.role === "web_researcher"
      );

      totalTokens += (result.usage?.input_tokens ?? 0) + (result.usage?.output_tokens ?? 0);

      if (result.toolCalls.length === 0) {
        // Try to parse findings from the final response
        try {
          const parsed = JSON.parse(result.content);
          if (Array.isArray(parsed)) {
            findings.push(...parsed);
          }
        } catch {
          // Non-JSON response — that's fine for preference analyst
          if (config.role === "preference_analyst" && result.content) {
            findings.push({
              source: "library",
              title: "User Preferences",
              relevance_note: result.content,
              confidence: 0.8,
            });
          }
        }
        break;
      }

      // Process tool calls
      messages.push({
        role: "assistant",
        content: formatAssistantContent(result),
      });

      for (const tc of result.toolCalls) {
        await emitStatus(supabase, curationId, {
          type: "agent_progress",
          agentRole: config.role,
          agentTaskId: taskId,
          message: `${roleDisplayName(config.role)}: ${toolDisplayName(tc.name)}`,
        });

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

        // Try to extract findings from search results
        try {
          const parsed = JSON.parse(toolResult);
          if (parsed.results && Array.isArray(parsed.results)) {
            for (const r of parsed.results) {
              if (r.title) {
                findings.push({
                  source: tc.name.includes("web") ? "web" : "library",
                  content_id: r.id,
                  url: r.url,
                  title: r.title,
                  author: r.author,
                  summary: r.summary ?? r.snippet,
                  relevance_note: "",
                  confidence: 0.5,
                });
              }
            }
          }
        } catch {
          // Not parseable, skip
        }
      }
    }
  } catch (error) {
    console.error(`Subagent ${config.role} error:`, error);
    await supabase
      .from("agent_tasks")
      .update({
        status: "error",
        error_message: String(error),
        completed_at: new Date().toISOString(),
      })
      .eq("id", taskId);

    await emitStatus(supabase, curationId, {
      type: "agent_complete",
      agentRole: config.role,
      agentTaskId: taskId,
      message: `${roleDisplayName(config.role)}: error`,
      finding: `Error: ${String(error).slice(0, 100)}`,
    });

    return { findings: [], tokensUsed: totalTokens };
  }

  // Deduplicate findings by title
  const seen = new Set<string>();
  const uniqueFindings = findings.filter((f) => {
    const key = f.title.toLowerCase().trim();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });

  // Update task record
  await supabase
    .from("agent_tasks")
    .update({
      status: "completed",
      findings: uniqueFindings,
      tokens_used: totalTokens,
      completed_at: new Date().toISOString(),
    })
    .eq("id", taskId);

  await emitStatus(supabase, curationId, {
    type: "agent_complete",
    agentRole: config.role,
    agentTaskId: taskId,
    message: `${roleDisplayName(config.role)}: found ${uniqueFindings.length} items`,
    finding: `Found ${uniqueFindings.length} relevant items`,
  });

  return { findings: uniqueFindings, tokensUsed: totalTokens };
}

// --- Synthesis ---

async function synthesizeAndCreateItems(
  supabase: SupabaseClient,
  curationId: string,
  allFindings: Finding[],
  request: CuratorRequest,
  history: { role: string; content: string }[]
): Promise<void> {
  await emitStatus(supabase, curationId, {
    type: "synthesis_start",
    message: "Evaluating and ranking findings...",
  });

  const provider = resolveProvider(request.model ?? "claude");
  const modelId = resolveModelId(request.model ?? "claude", provider);

  const synthesisPrompt = `You are synthesizing research findings into a curated reading list for the LastFirst reading app.

Given findings from multiple research agents, create a final curated list:
1. Deduplicate (same content found by multiple agents)
2. Rank by relevance to the user's original query and quality
3. Select the top 5-10 most relevant items
4. Generate a personalized agent_note for each explaining why it's recommended
5. Write a conversational summary of what you found

Respond with JSON:
{
  "summary": "Conversational response to the user about what you found",
  "items": [
    {
      "content_id": "uuid or null",
      "external_url": "url or null",
      "external_title": "title",
      "external_author": "author",
      "external_summary": "brief summary",
      "agent_note": "personalized recommendation note",
      "item_type": "book|article|paper|content|external_link",
      "confidence": 0.9
    }
  ]
}`;

  const conversationContext = history.length > 0
    ? `\n\nConversation context:\n${history.map((m) => `${m.role}: ${m.content.slice(0, 200)}`).join("\n")}`
    : "";

  const result = await callLLM(
    provider,
    synthesisPrompt,
    [
      {
        role: "user",
        content: `Original query: "${request.message}"${conversationContext}\n\nFindings from research agents (${allFindings.length} total):\n${JSON.stringify(allFindings, null, 2)}`,
      },
    ],
    modelId,
    undefined,
    4096
  );

  // Parse synthesis result
  let synthesis: { summary: string; items: Record<string, unknown>[] };
  try {
    const cleaned = result.content.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
    synthesis = JSON.parse(cleaned);
  } catch {
    // Fallback: use raw content as summary, create items from top findings
    synthesis = {
      summary: result.content,
      items: allFindings
        .sort((a, b) => b.confidence - a.confidence)
        .slice(0, 7)
        .map((f) => ({
          content_id: f.content_id ?? null,
          external_url: f.url ?? null,
          external_title: f.title,
          external_author: f.author,
          external_summary: f.summary,
          agent_note: f.relevance_note,
          item_type: f.source === "library" ? "content" : "external_link",
        })),
    };
  }

  // Create curation items
  for (let i = 0; i < (synthesis.items ?? []).length; i++) {
    const item = synthesis.items[i];
    const insertData: Record<string, unknown> = {
      curation_id: curationId,
      item_type: item.item_type ?? "external_link",
      position: i,
      agent_note: item.agent_note,
    };

    if (item.content_id) insertData.content_id = item.content_id;
    if (item.external_url) insertData.external_url = item.external_url;
    if (item.external_title) insertData.external_title = item.external_title;
    if (item.external_author) insertData.external_author = item.external_author;
    if (item.external_summary) insertData.external_summary = item.external_summary;

    await supabase.from("curation_items").insert(insertData);
  }

  // Save assistant message
  await supabase.from("curation_messages").insert({
    curation_id: curationId,
    role: "assistant",
    content: synthesis.summary,
  });
}
