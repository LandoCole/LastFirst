from __future__ import annotations

import json
import logging
import uuid
from typing import Any

logger = logging.getLogger(__name__)

from app.config import Settings
from app.models import (
    ClarificationQuestion,
    ClassificationResult,
    CuratorChatRequest,
    CuratorChatResponse,
    Finding,
    SubagentResult,
)
from app.services.anthropic_client import AnthropicService
from app.services.semantic_vault import SemanticVaultService
from app.services.supabase_repository import SupabaseRepository
from app.services.tools import TOOL_DEFINITIONS, ToolExecutor

CURATOR_SYSTEM_PROMPT = """You are the Curator, an AI research agent for the LastFirst reading app. Your job is to help users discover books, articles, papers, and other reading material.

You have access to tools to search the internal library, fetch URLs, and add items to curations. You also have built-in web search capability for finding content online. Use multiple search strategies to find the best results.

When you find relevant content, use create_curation_item to add it to the curation with a personalized agent_note explaining why you're recommending it.

When you find content via web search, use ingest_url to scrape the URL for real metadata (word count, reading time, cover image). Pass enriched metadata when calling create_curation_item: external_word_count, external_estimated_read_minutes, external_file_type, external_availability, external_image_url.

Your chat response should be a brief research summary (2-4 sentences) about what you found and why these items are relevant. Do NOT list each item in detail -- the structured content cards will display that.

Be conversational but efficient. Always search before recommending. Prefer library content when available, supplement with web finds."""

CLASSIFIER_PROMPT = """You classify user queries for a reading curation agent. Respond with ONLY valid JSON.

Categories:
- SIMPLE: ONLY for requests for a single specific title or author. Examples: "Find The Art of War", "Do we have any Hemingway?", "Get me Sapiens by Yuval Noah Harari"
- MODERATE: Any topic-based or exploratory query. This is the DEFAULT for most queries. Examples: "Find me things to read about mars", "Recommend philosophy books", "Articles about stoicism", "Something about AI", "Good books on leadership"
- COMPLEX: Multi-topic, cross-domain, or research-intensive. Examples: "Research the intersection of AI and philosophy — books, papers, and articles", "Compare different schools of thought on consciousness"

IMPORTANT: If in doubt between SIMPLE and MODERATE, choose MODERATE. Only use SIMPLE when the user names a specific title or asks for a specific author's works.

For MODERATE/COMPLEX, decompose into focused subqueries with roles:
- library_searcher: searches internal content catalog
- web_researcher: finds external content on the web

Response format:
{"complexity":"simple|moderate|complex","subqueries":[{"role":"library_searcher|web_researcher","query":"focused query"}],"reasoning":"brief explanation"}"""

CLARIFICATION_PROMPT = """You generate clarification questions for a reading curation agent. Given a user's query, produce 1-3 follow-up questions that would help narrow down the best recommendations.

Rules:
- Questions should be specific to the user's query, NOT generic
- Each question has 2-4 options with short labels (2-4 words) and optional emoji
- selection_type: "single" when choices are mutually exclusive, "multi" when the user might want several
- Do NOT ask about topics the user already specified
- Focus on: content type, length/depth, recency, accessibility, difficulty level, perspective, format

Respond with ONLY valid JSON:
{
  "intro": "Brief friendly message (1 sentence) acknowledging the query and saying you have a few questions",
  "questions": [
    {
      "id": "q1",
      "question": "What kind of content works best for you?",
      "selection_type": "multi",
      "options": [
        {"id": "q1_a", "label": "Books", "emoji": "📚"},
        {"id": "q1_b", "label": "Articles", "emoji": "📰"},
        {"id": "q1_c", "label": "Research papers", "emoji": "📄"}
      ]
    }
  ]
}"""

# Tool definitions for the chat service include create_curation_item
CHAT_TOOL_DEFINITIONS = TOOL_DEFINITIONS + [
    {
        "name": "create_curation_item",
        "description": "Add an item to the current curation. Can be internal content or an external link.",
        "input_schema": {
            "type": "object",
            "properties": {
                "curation_id": {"type": "string", "description": "Curation UUID"},
                "content_id": {"type": "string", "description": "Content UUID (for library items)"},
                "external_url": {"type": "string", "description": "External URL (for web items)"},
                "external_title": {"type": "string", "description": "Title for external items"},
                "external_author": {"type": "string", "description": "Author for external items"},
                "external_summary": {"type": "string", "description": "Summary for external items"},
                "agent_note": {
                    "type": "string",
                    "description": "Curator's personalized note about why this item is recommended",
                },
                "item_type": {
                    "type": "string",
                    "enum": ["content", "external_link", "book", "article", "paper", "pdf"],
                    "description": "Type of item",
                },
                "external_word_count": {"type": "number", "description": "Word count for external items"},
                "external_estimated_read_minutes": {"type": "number", "description": "Estimated reading time in minutes"},
                "external_file_type": {"type": "string", "description": "Content format: web, pdf, epub"},
                "external_availability": {"type": "string", "description": "full_text, downloadable, external_purchase, or paywalled"},
                "external_image_url": {"type": "string", "description": "Cover or preview image URL"},
            },
            "required": ["curation_id", "item_type"],
        },
    },
]

SUBAGENT_TOOLS: dict[str, list[str]] = {
    "preference_analyst": ["get_user_reading_history"],
    "library_searcher": ["search_content", "get_content_details"],
    "web_researcher": ["ingest_url"],
}

SUBAGENT_MAX_ITERATIONS: dict[str, int] = {
    "preference_analyst": 3,
    "library_searcher": 5,
    "web_researcher": 7,
}

ROLE_DISPLAY_NAMES: dict[str, str] = {
    "preference_analyst": "Preference Analyst",
    "library_searcher": "Library Searcher",
    "web_researcher": "Web Researcher",
}


def _get_subagent_prompt(role: str, user_preferences: list[Finding] | None = None) -> str:
    pref_context = ""
    if user_preferences:
        pref_context = f"\n\nUser preference context (from reading history analysis):\n{json.dumps([f.model_dump() for f in user_preferences], indent=2)}"

    if role == "preference_analyst":
        return (
            "You analyze a user's reading history to infer their interests, preferences, and reading patterns. "
            "Examine their interactions, reading sessions, and past curations. Return structured findings about their preferences as a JSON array of findings.\n\n"
            'Each finding should be: {"source":"library","title":"Preference insight","relevance_note":"description of the pattern","confidence":0.8}\n\n'
            "Focus on: genres they gravitate toward, authors they follow, topics of interest, reading frequency patterns, content types they prefer."
        )
    if role == "library_searcher":
        return (
            f"You are a Library Searcher agent for the LastFirst reading app. Search the internal content library thoroughly using multiple query variations to find relevant items.{pref_context}\n\n"
            "For each relevant item found, include it in your findings. Try at least 2-3 different search queries to maximize coverage. Return findings as a JSON array.\n\n"
            'Each finding: {"source":"library","content_id":"uuid","title":"...","author":"...","summary":"...","relevance_note":"why this is relevant","confidence":0.0-1.0}'
        )
    if role == "web_researcher":
        return (
            f"You are a Web Researcher agent for the LastFirst reading app. You have built-in web search capability and the ingest_url tool.{pref_context}\n\n"
            "WORKFLOW:\n"
            "1. Use web search to discover relevant content URLs\n"
            "2. For each promising URL (top 3-5), call ingest_url to scrape it and get real metadata (word count, reading time, cover image, author)\n"
            "3. If ingest_url fails for a URL, include the finding with whatever metadata you have from web search, and infer what you can\n"
            "4. Return findings as a JSON array\n\n"
            "Each finding:\n"
            '{"source":"web","content_id":"uuid from ingest_url or null","url":"...","title":"...","author":"...",'
            '"summary":"2-3 sentence summary","word_count":1234,"estimated_read_minutes":5,'
            '"file_type":"web|pdf|epub","availability":"full_text|external_purchase|paywalled",'
            '"image_url":"cover/preview image URL or null",'
            '"relevance_note":"why this is relevant","confidence":0.0-1.0}\n\n'
            "Prioritize quality over quantity. Scrape 3-5 best URLs rather than many."
        )
    return CURATOR_SYSTEM_PROMPT


class CuratorChatService:
    def __init__(
        self,
        *,
        repository: SupabaseRepository,
        anthropic: AnthropicService,
        semantic_vault: SemanticVaultService,
        settings: Settings,
    ) -> None:
        self._repository = repository
        self._anthropic = anthropic
        self._semantic_vault = semantic_vault
        self._settings = settings
        self._tools = ToolExecutor(repository, semantic_vault)

    async def handle(self, request: CuratorChatRequest) -> CuratorChatResponse:
        user_id = request.user_id
        if not user_id:
            raise ValueError("user_id is required")

        curation_id = self._get_or_create_curation(request, user_id)

        # Check if this is a clarification response
        effective_message = request.message
        skip_clarification = False
        clarification_response = self._parse_clarification_response(request.message)
        if clarification_response:
            effective_message = self._build_enriched_query(clarification_response)
            skip_clarification = True
            readable_parts = [
                ", ".join(s.get("selected_labels", []))
                for s in clarification_response.get("selections", [])
                if s.get("selected_labels")
            ]
            self._repository.insert_curation_message(
                curation_id, "user", " · ".join(readable_parts) or request.message
            )
        else:
            self._repository.insert_curation_message(curation_id, "user", request.message)

        history = self._get_conversation_history(curation_id)
        classification = await self._classify_query(effective_message, history)

        total_agents = 1 if classification.complexity == "simple" else len(classification.subqueries) + 1
        self._repository.update_curation(
            curation_id,
            {"complexity": classification.complexity, "agent_count": total_agents},
        )

        # Clarification gate
        print(f"[clarification] Gate: complexity={classification.complexity}, skip={skip_clarification}")
        if classification.complexity != "simple" and not skip_clarification:
            clarification = await self._generate_clarification_questions(effective_message, history)
            if clarification:
                self._repository.insert_curation_message(
                    curation_id, "assistant", clarification["intro"]
                )
                return CuratorChatResponse(
                    curation_id=curation_id,
                    response=clarification["intro"],
                    clarification_questions=clarification["questions"],
                    complexity=classification.complexity,
                    agent_count=total_agents,
                )

        # Use enriched message for research
        if clarification_response:
            request = CuratorChatRequest(
                curation_id=request.curation_id,
                message=effective_message,
                user_id=request.user_id,
                model=request.model,
            )

        if classification.complexity == "simple":
            return await self._run_simple(curation_id, request, history, classification, total_agents)

        return await self._run_multi_agent(curation_id, request, history, classification, total_agents)

    # --- Simple inline loop ---

    async def _run_simple(
        self,
        curation_id: str,
        request: CuratorChatRequest,
        history: list[dict[str, str]],
        classification: ClassificationResult,
        total_agents: int,
    ) -> CuratorChatResponse:
        self._emit_status(curation_id, {
            "type": "plan",
            "plan": [
                {"label": "Search", "description": "Looking for relevant content"},
                {"label": "Evaluate", "description": "Reviewing and selecting the best matches"},
                {"label": "Curate", "description": "Adding items with personalized notes"},
            ],
        })

        messages: list[dict[str, Any]] = [{"role": m["role"], "content": m["content"]} for m in history]
        items_added = 0
        active_step: int | None = None
        completed_steps: set[int] = set()

        step_start_msgs = ["Searching for relevant content...", "Reviewing promising matches...", "Adding recommendations to your curation..."]
        step_complete_msgs = ["Search complete", "Evaluation complete", "Curation complete"]
        tool_step_map = {
            "search_content": 0,
            "get_content_details": 1,
        }

        for _ in range(10):
            result = await self._anthropic.call_with_tools(
                system_prompt=CURATOR_SYSTEM_PROMPT,
                messages=messages,
                model=self._settings.agent_default_model,
                tools=CHAT_TOOL_DEFINITIONS,
                max_tokens=4096,
                enable_web_search=True,
            )

            if not result.tool_calls:
                if active_step is not None and active_step not in completed_steps:
                    self._emit_status(curation_id, {
                        "type": "step_complete",
                        "stepIndex": active_step,
                        "message": step_complete_msgs[active_step] if active_step < len(step_complete_msgs) else "Step complete",
                    })
                self._repository.insert_curation_message(curation_id, "assistant", result.content)
                self._repository.update_curation(curation_id, {"status": "ready"})
                return CuratorChatResponse(
                    curation_id=curation_id,
                    response=result.content,
                    items_added=items_added,
                    complexity=classification.complexity,
                    agent_count=total_agents,
                )

            messages.append({
                "role": "assistant",
                "content": self._format_assistant_content(result.content, result.tool_calls, result.raw_content),
            })

            for tc in result.tool_calls:
                step_index = tool_step_map.get(tc.name, 2)

                if active_step != step_index:
                    if active_step is not None and active_step not in completed_steps:
                        self._emit_status(curation_id, {
                            "type": "step_complete",
                            "stepIndex": active_step,
                            "message": step_complete_msgs[active_step] if active_step < len(step_complete_msgs) else "Step complete",
                        })
                        completed_steps.add(active_step)
                    if step_index not in completed_steps:
                        self._emit_status(curation_id, {
                            "type": "step_start",
                            "stepIndex": step_index,
                            "message": step_start_msgs[step_index] if step_index < len(step_start_msgs) else "Working...",
                        })
                    active_step = step_index

                if tc.name == "create_curation_item":
                    tool_result = await self._execute_create_item(curation_id, tc.input)
                    items_added += 1
                    self._emit_status(curation_id, {
                        "type": "finding",
                        "stepIndex": 2,
                        "finding": f"Added: {tc.input.get('external_title') or 'library item'}",
                    })
                else:
                    tool_result = await self._tools.execute(tc.name, tc.input)

                self._emit_status(curation_id, {
                    "type": "step_progress",
                    "stepIndex": step_index,
                    "tool": tc.name,
                    "message": self._tool_display_name(tc.name),
                })

                messages.append({
                    "role": "user",
                    "content": [{"type": "tool_result", "tool_use_id": tc.id, "content": tool_result}],
                })

        # Hit max iterations
        if active_step is not None and active_step not in completed_steps:
            self._emit_status(curation_id, {
                "type": "step_complete",
                "stepIndex": active_step,
                "message": step_complete_msgs[active_step] if active_step < len(step_complete_msgs) else "Step complete",
            })

        response_text = "I've finished researching. Check the curated items above!"
        self._repository.insert_curation_message(curation_id, "assistant", response_text)
        self._repository.update_curation(curation_id, {"status": "ready"})
        return CuratorChatResponse(
            curation_id=curation_id,
            response=response_text,
            items_added=items_added,
            complexity=classification.complexity,
            agent_count=total_agents,
        )

    # --- Multi-agent orchestration ---

    async def _run_multi_agent(
        self,
        curation_id: str,
        request: CuratorChatRequest,
        history: list[dict[str, str]],
        classification: ClassificationResult,
        total_agents: int,
    ) -> CuratorChatResponse:
        self._emit_status(curation_id, {
            "type": "agent_spawned",
            "totalAgents": total_agents,
            "message": f"Launching {total_agents} research agents...",
        })
        self._repository.update_curation(curation_id, {"status": "researching"})

        try:
            # 1. Run preference analyst
            pref_result = await self._run_subagent(
                curation_id=curation_id,
                role="preference_analyst",
                query="Analyze user reading history and preferences",
                user_id=request.user_id or "",
            )

            # 2. Run remaining subagents (could be parallelized later with asyncio.gather)
            all_findings: list[Finding] = []
            for sq in classification.subqueries:
                sub_result = await self._run_subagent(
                    curation_id=curation_id,
                    role=sq["role"],
                    query=sq["query"],
                    user_id=request.user_id or "",
                    user_preferences=pref_result.findings,
                )
                all_findings.extend(sub_result.findings)

            # 3. Synthesize
            await self._synthesize(curation_id, all_findings, request, history)

            # 4. Mark ready
            self._repository.update_curation(
                curation_id,
                {"status": "ready", "complexity": classification.complexity},
            )
        except Exception as exc:
            self._repository.update_curation(
                curation_id,
                {"status": "error", "error_message": str(exc)},
            )
            self._emit_status(curation_id, {
                "type": "error",
                "message": f"Research failed: {exc}",
            })

        # Return immediately — app polls for completion
        return CuratorChatResponse(
            curation_id=curation_id,
            complexity=classification.complexity,
            agent_count=total_agents,
        )

    async def _run_subagent(
        self,
        *,
        curation_id: str,
        role: str,
        query: str,
        user_id: str,
        user_preferences: list[Finding] | None = None,
    ) -> SubagentResult:
        system_prompt = _get_subagent_prompt(role, user_preferences)
        tool_names = SUBAGENT_TOOLS.get(role, [])
        tools = [t for t in TOOL_DEFINITIONS if t["name"] in tool_names]
        max_iter = SUBAGENT_MAX_ITERATIONS.get(role, 5)

        task_id = self._repository.create_agent_task(curation_id, role, query)
        display_name = ROLE_DISPLAY_NAMES.get(role, role)
        self._emit_status(curation_id, {
            "type": "agent_progress",
            "agentRole": role,
            "agentTaskId": task_id,
            "message": f"{display_name}: starting...",
        })

        messages: list[dict[str, Any]] = [{"role": "user", "content": query}]
        findings: list[Finding] = []
        total_tokens = 0

        try:
            for _ in range(max_iter):
                result = await self._anthropic.call_with_tools(
                    system_prompt=system_prompt,
                    messages=messages,
                    model=self._settings.agent_default_model,
                    tools=tools if tools else None,
                    max_tokens=4096,
                    enable_web_search=role == "web_researcher",
                )
                if result.usage:
                    total_tokens += (result.usage.get("input_tokens", 0) + result.usage.get("output_tokens", 0))

                if not result.tool_calls:
                    try:
                        parsed = json.loads(result.content)
                        if isinstance(parsed, list):
                            for item in parsed:
                                findings.append(Finding.model_validate(item))
                    except (json.JSONDecodeError, Exception):
                        if role == "preference_analyst" and result.content:
                            findings.append(Finding(
                                source="library",
                                title="User Preferences",
                                relevance_note=result.content,
                                confidence=0.8,
                            ))
                    break

                messages.append({
                    "role": "assistant",
                    "content": self._format_assistant_content(result.content, result.tool_calls, result.raw_content),
                })

                for tc in result.tool_calls:
                    self._emit_status(curation_id, {
                        "type": "agent_progress",
                        "agentRole": role,
                        "agentTaskId": task_id,
                        "message": f"{display_name}: {self._tool_display_name(tc.name)}",
                    })
                    tool_result = await self._tools.execute(tc.name, tc.input)
                    messages.append({
                        "role": "user",
                        "content": [{"type": "tool_result", "tool_use_id": tc.id, "content": tool_result}],
                    })

                    # Extract findings from search results
                    try:
                        parsed = json.loads(tool_result)
                        for r in parsed.get("results", []):
                            if r.get("title"):
                                findings.append(Finding(
                                    source="web" if "web" in tc.name else "library",
                                    content_id=r.get("id"),
                                    url=r.get("url"),
                                    title=r["title"],
                                    author=r.get("author"),
                                    summary=r.get("summary") or r.get("snippet"),
                                    confidence=0.5,
                                ))
                    except (json.JSONDecodeError, Exception):
                        pass

        except Exception as exc:
            self._repository.complete_agent_task(task_id, "error", error_message=str(exc))
            self._emit_status(curation_id, {
                "type": "agent_complete",
                "agentRole": role,
                "agentTaskId": task_id,
                "message": f"{display_name}: error",
                "finding": f"Error: {str(exc)[:100]}",
            })
            return SubagentResult(findings=[], tokens_used=total_tokens)

        # Deduplicate by title
        seen: set[str] = set()
        unique: list[Finding] = []
        for f in findings:
            key = f.title.lower().strip()
            if key not in seen:
                seen.add(key)
                unique.append(f)

        self._repository.complete_agent_task(
            task_id, "completed",
            findings=[f.model_dump() for f in unique],
            tokens_used=total_tokens,
        )
        self._emit_status(curation_id, {
            "type": "agent_complete",
            "agentRole": role,
            "agentTaskId": task_id,
            "message": f"{display_name}: found {len(unique)} items",
            "finding": f"Found {len(unique)} relevant items",
        })
        return SubagentResult(findings=unique, tokens_used=total_tokens)

    async def _synthesize(
        self,
        curation_id: str,
        all_findings: list[Finding],
        request: CuratorChatRequest,
        history: list[dict[str, str]],
    ) -> None:
        self._emit_status(curation_id, {
            "type": "synthesis_start",
            "message": "Evaluating and ranking findings...",
        })

        synthesis_prompt = """You are synthesizing research findings into a curated reading list for the LastFirst reading app.

Given findings from multiple research agents, create a final curated list:
1. Deduplicate (same content found by multiple agents)
2. Rank by relevance to the user's original query and quality
3. Select the top 5-10 most relevant items
4. Generate a personalized agent_note for each explaining why it's recommended
5. Write a brief conversational summary (2-4 sentences) of what you found -- do NOT list each item in detail
6. Pass through all metadata from findings including word_count, estimated_read_minutes, file_type, availability, and image_url

Respond with JSON:
{
  "summary": "Brief conversational overview of what you found and why (2-4 sentences)",
  "items": [
    {
      "content_id": "uuid or null",
      "external_url": "url or null",
      "external_title": "title",
      "external_author": "author",
      "external_summary": "brief summary",
      "external_word_count": 1234,
      "external_estimated_read_minutes": 5,
      "external_file_type": "web|pdf|epub",
      "external_availability": "full_text|external_purchase|paywalled",
      "external_image_url": "image URL or null",
      "agent_note": "personalized recommendation note",
      "item_type": "book|article|paper|content|external_link",
      "confidence": 0.9
    }
  ]
}"""

        context = ""
        if history:
            context = "\n\nConversation context:\n" + "\n".join(
                f"{m['role']}: {m['content'][:200]}" for m in history
            )

        findings_json = json.dumps([f.model_dump() for f in all_findings], indent=2)
        result = await self._anthropic.call_with_tools(
            system_prompt=synthesis_prompt,
            messages=[{
                "role": "user",
                "content": f'Original query: "{request.message}"{context}\n\nFindings from research agents ({len(all_findings)} total):\n{findings_json}',
            }],
            model=self._settings.agent_default_model,
            max_tokens=4096,
        )

        try:
            cleaned = result.content.replace("```json", "").replace("```", "").strip()
            synthesis = json.loads(cleaned)
        except json.JSONDecodeError:
            synthesis = {
                "summary": result.content,
                "items": [
                    {
                        "content_id": f.content_id,
                        "external_url": f.url,
                        "external_title": f.title,
                        "external_author": f.author,
                        "external_summary": f.summary,
                        "external_word_count": f.word_count,
                        "external_estimated_read_minutes": f.estimated_read_minutes,
                        "external_file_type": f.file_type,
                        "external_availability": f.availability,
                        "external_image_url": f.image_url,
                        "agent_note": f.relevance_note,
                        "item_type": "content" if f.source == "library" else "external_link",
                    }
                    for f in sorted(all_findings, key=lambda x: x.confidence, reverse=True)[:7]
                ],
            }

        items = synthesis.get("items", [])
        self._repository.insert_curation_items(curation_id, items)
        self._repository.insert_curation_message(
            curation_id, "assistant", synthesis.get("summary") or result.content,
        )

    # --- Helpers ---

    def _get_or_create_curation(self, request: CuratorChatRequest, user_id: str) -> str:
        if request.curation_id:
            curation = self._repository.get_curation(request.curation_id)
            if not curation:
                raise ValueError("Curation not found")
            if curation.get("user_id") != user_id:
                raise ValueError("You do not have access to this curation")
            return curation["id"]

        return self._repository.create_user_curation(user_id, request.message)

    def _get_conversation_history(self, curation_id: str) -> list[dict[str, str]]:
        return self._repository.get_conversation_history(curation_id)

    async def _classify_query(
        self, message: str, history: list[dict[str, str]]
    ) -> ClassificationResult:
        context_summary = ""
        if len(history) > 1:
            context_summary = f"\n\nConversation context ({len(history)} messages):\n" + "\n".join(
                f"{m['role']}: {m['content'][:200]}" for m in history[-4:]
            )

        try:
            result = await self._anthropic.call_with_tools(
                system_prompt=CLASSIFIER_PROMPT,
                messages=[{"role": "user", "content": f'Classify this query:{context_summary}\n\nUser query: "{message}"'}],
                model="claude-haiku-4-5-20251001",
                max_tokens=512,
            )
            parsed = json.loads(result.content.strip())
            return ClassificationResult(
                complexity=parsed.get("complexity", "simple"),
                subqueries=parsed.get("subqueries", []),
                reasoning=parsed.get("reasoning", ""),
                needs_clarification=parsed.get("needs_clarification", False),
            )
        except Exception as exc:
            return ClassificationResult(complexity="simple", reasoning=f"Classification failed: {exc}")

    async def _generate_clarification_questions(
        self, message: str, history: list[dict[str, str]]
    ) -> dict[str, Any] | None:
        print(f"[clarification] Generating questions for: {message[:100]}")
        try:
            context_summary = ""
            if len(history) > 1:
                context_summary = "\n\nConversation context:\n" + "\n".join(
                    f"{m['role']}: {m['content'][:200]}" for m in history[-4:]
                )
            result = await self._anthropic.call_with_tools(
                system_prompt=CLARIFICATION_PROMPT,
                messages=[{"role": "user", "content": f'User query: "{message}"{context_summary}'}],
                model="claude-haiku-4-5-20251001",
                max_tokens=1024,
            )
            print(f"[clarification] Raw LLM response: {result.content[:500]}")
            cleaned = result.content.replace("```json", "").replace("```", "").strip()
            parsed = json.loads(cleaned)
            questions = parsed.get("questions", [])
            if not questions:
                print("[clarification] LLM returned no questions")
                return None
            print(f"[clarification] Generated {len(questions)} questions")
            return {
                "intro": parsed.get("intro", "Before I start researching, a few quick questions."),
                "questions": [ClarificationQuestion(**q) for q in questions],
            }
        except Exception as exc:
            print(f"[clarification] Failed: {exc}")
            return None

    @staticmethod
    def _parse_clarification_response(message: str) -> dict[str, Any] | None:
        try:
            parsed = json.loads(message)
            if parsed.get("__clarification_response") is True:
                return parsed
        except (json.JSONDecodeError, TypeError):
            pass
        return None

    @staticmethod
    def _build_enriched_query(clarification: dict[str, Any]) -> str:
        enriched = clarification.get("original_query", "")
        selections = clarification.get("selections", [])
        if selections:
            enriched += "\n\nUser preferences:"
            for sel in selections:
                labels = ", ".join(sel.get("selected_labels", []))
                enriched += f"\n- {sel.get('question_text', '')}: {labels}"
        return enriched

    async def _execute_create_item(self, curation_id: str, input_data: dict[str, Any]) -> str:
        existing_items = self._repository.get_curation_item_count(curation_id)
        item: dict[str, Any] = {
            "curation_id": curation_id,
            "item_type": input_data.get("item_type", "content"),
            "position": existing_items,
        }
        for field in (
            "content_id", "external_url", "external_title", "external_author", "external_summary", "agent_note",
            "external_word_count", "external_estimated_read_minutes", "external_file_type",
            "external_availability", "external_image_url",
        ):
            if input_data.get(field):
                item[field] = input_data[field]

        self._repository.insert_single_curation_item(item)
        return json.dumps({"success": True, "position": existing_items})

    def _emit_status(self, curation_id: str, status: dict[str, Any]) -> None:
        self._repository.insert_curation_message(curation_id, "tool", json.dumps(status))

    def _format_assistant_content(
        self, content: str, tool_calls: list[Any], raw_content: list[dict[str, Any]] | None = None
    ) -> list[dict[str, Any]]:
        if raw_content is not None:
            return raw_content
        blocks: list[dict[str, Any]] = []
        if content:
            blocks.append({"type": "text", "text": content})
        for tc in tool_calls:
            blocks.append({"type": "tool_use", "id": tc.id, "name": tc.name, "input": tc.input})
        return blocks

    @staticmethod
    def _tool_display_name(name: str) -> str:
        names = {
            "search_content": "Searching library",
            "get_content_details": "Getting details",
            "get_user_reading_history": "Reviewing reading history",
            "create_curation_item": "Adding to curation",
            "ingest_url": "Ingesting content",
            "search_vault_notes": "Searching knowledge graph",
            "get_vault_note": "Reading note",
            "get_vault_backlinks": "Following backlinks",
        }
        return names.get(name, name)
