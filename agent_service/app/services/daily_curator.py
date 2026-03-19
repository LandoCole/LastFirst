from __future__ import annotations

import json
from collections import defaultdict
from datetime import UTC, datetime
from typing import Any

from app.config import Settings
from app.models import DailyCurationConfig, DailyRunRequest, DailyRunResponse, Finding
from app.services.anthropic_client import AnthropicService
from app.services.firecrawl import FirecrawlService
from app.services.semantic_vault import SemanticVaultService
from app.services.supabase_repository import SupabaseRepository
from app.services.tools import TOOL_DEFINITIONS, ToolExecutor

DAILY_SYSTEM_PROMPT = """You are the Daily Curator for the LastFirst reading app. Your job is to create a personalized daily reading curation for a user based on their reading history, current reading momentum, and long-term interests.

Priorities:
1. Balance complementary readings for what the user is reading now with broader interests from their library and history.
1b. Use the user's knowledge graph notes to recover goals, themes, open questions, and related concepts before broadening to external sources.
2. Prefer high-quality, reliable, and readable sources.
3. Diversify across source types when it improves the curation.
4. Prefer items with readable full text over metadata-only links when relevance is comparable.
5. Ingest especially strong external readings into the library when that improves future retrieval.

Use the tools to inspect the user's reading history, search the knowledge graph, follow backlinks, search the library, search the web, fetch source pages, ingest strong external sources, and write a concise daily reflection note.

Return only valid JSON:
{
  "title": "Short curation title",
  "summary": "Why these picks fit today",
  "items": [
    {
      "content_id": "uuid or null",
      "external_url": "url or null",
      "external_title": "title",
      "external_author": "author",
      "external_summary": "summary",
      "agent_note": "why this is recommended",
      "item_type": "book|article|paper|content|external_link"
    }
  ]
}"""


class DailyCuratorService:
    def __init__(
        self,
        *,
        repository: SupabaseRepository,
        anthropic: AnthropicService,
        firecrawl: FirecrawlService,
        semantic_vault: SemanticVaultService,
        settings: Settings,
    ) -> None:
        self._repository = repository
        self._anthropic = anthropic
        self._firecrawl = firecrawl
        self._semantic_vault = semantic_vault
        self._settings = settings
        self._tools = ToolExecutor(repository, firecrawl, semantic_vault)

    async def run(self, request: DailyRunRequest) -> DailyRunResponse:
        configs = self._repository.list_daily_configs(user_id=request.user_id, max_users=request.max_users)
        processed_users = 0
        created_curations = 0
        skipped_users = 0
        results: list[dict[str, Any]] = []

        for config in configs:
            if not self._is_due(config):
                skipped_users += 1
                results.append({"user_id": config.user_id, "status": "skipped_not_due"})
                continue

            if self._repository.has_daily_curation_today(config.user_id):
                skipped_users += 1
                results.append({"user_id": config.user_id, "status": "skipped_existing_today"})
                continue

            processed_users += 1
            if request.dry_run:
                results.append({"user_id": config.user_id, "status": "dry_run_eligible"})
                continue

            result = await self._generate_for_user(config)
            results.append(result)
            if result.get("status") == "created":
                created_curations += 1
                self._repository.mark_daily_generated(config.id)

        return DailyRunResponse(
            processed_users=processed_users,
            created_curations=created_curations,
            skipped_users=skipped_users,
            results=results,
        )

    async def _generate_for_user(self, config: DailyCurationConfig) -> dict[str, Any]:
        curation_id = self._repository.create_daily_curation(config.user_id)
        self._repository.insert_curation_message(
            curation_id,
            "tool",
            json.dumps({"type": "agent_progress", "message": "Daily curator started"}),
        )

        try:
            user_state = self._build_user_state_payload(config.user_id)
            vault_context = await self._build_vault_context(config.user_id, user_state)
            messages: list[dict[str, Any]] = [
                {
                    "role": "user",
                    "content": (
                        f"Create a daily curation for user {config.user_id}. "
                        f"Find up to {config.max_items or self._settings.agent_default_max_items} recommendations. "
                        f"Today is {datetime.now(UTC).strftime('%A, %B %d, %Y')}.\n\n"
                        f"Weighted user state:\n{json.dumps(user_state, indent=2)}\n\n"
                        f"Vault context:\n{json.dumps(vault_context, indent=2)}"
                    ),
                }
            ]

            for _ in range(8):
                result = await self._anthropic.call_with_tools(
                    system_prompt=DAILY_SYSTEM_PROMPT,
                    messages=messages,
                    model=self._settings.agent_default_model,
                    tools=TOOL_DEFINITIONS,
                    max_tokens=4096,
                )

                if not result.tool_calls:
                    return await self._finalize_curation(
                        curation_id=curation_id,
                        user_id=config.user_id,
                        max_items=config.max_items,
                        raw_content=result.content,
                    )

                messages.append(
                    {
                        "role": "assistant",
                        "content": self._format_assistant_content(result.content, result.tool_calls),
                    }
                )

                for tool_call in result.tool_calls:
                    self._repository.insert_curation_message(
                        curation_id,
                        "tool",
                        json.dumps(
                            {
                                "type": "agent_progress",
                                "message": f"Daily curator: {tool_call.name}",
                            }
                        ),
                    )
                    tool_result = await self._tools.execute(tool_call.name, tool_call.input)
                    messages.append(
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "tool_result",
                                    "tool_use_id": tool_call.id,
                                    "content": tool_result,
                                }
                            ],
                        }
                    )

            self._repository.update_curation(curation_id, {"status": "ready", "summary": "Daily curation finished with partial results."})
            await self._write_daily_reflection(
                user_id=config.user_id,
                summary="Daily curation finished with partial results.",
                items=[],
            )
            return {"user_id": config.user_id, "curation_id": curation_id, "status": "created_partial"}
        except Exception as exc:
            self._repository.update_curation(
                curation_id,
                {"status": "error", "error_message": str(exc)},
            )
            self._repository.insert_curation_message(
                curation_id,
                "tool",
                json.dumps({"type": "error", "message": f"Daily curator failed: {exc}"}),
            )
            return {"user_id": config.user_id, "curation_id": curation_id, "status": "error", "error": str(exc)}

    def _is_due(self, config: DailyCurationConfig) -> bool:
        now = datetime.now(UTC)
        return now.hour >= int(config.generation_hour)

    def _build_user_state_payload(self, user_id: str) -> dict[str, Any]:
        history = self._repository.get_user_reading_history(
            user_id,
            limit=self._settings.agent_default_history_limit,
        )
        interactions = history.get("interactions", [])
        sessions = history.get("reading_sessions", [])
        past_curations = history.get("past_curations", [])

        content_scores: dict[str, float] = defaultdict(float)
        content_titles: dict[str, str] = {}
        content_authors: dict[str, str] = {}

        for index, interaction in enumerate(interactions):
            content = interaction.get("content") or {}
            content_id = content.get("id")
            if not content_id:
                continue
            recency_weight = max(0.2, 1.0 - (index * 0.04))
            kind = str(interaction.get("kind") or "open").lower()
            kind_weight = 2.5 if kind in {"save", "bookmark", "favorite"} else 1.5 if kind in {"open", "read"} else 1.0
            content_scores[content_id] += recency_weight * kind_weight
            content_titles[content_id] = content.get("title") or "Untitled"
            content_authors[content_id] = content.get("author") or ""

        for index, session in enumerate(sessions):
            content_id = session.get("content_id")
            if not content_id:
                continue
            recency_weight = max(0.2, 1.0 - (index * 0.04))
            duration = float(session.get("duration_seconds") or 0)
            pages_read = float(session.get("pages_read") or 0)
            content_scores[content_id] += recency_weight * ((duration / 600.0) + (pages_read * 0.35) + 1.0)

        content_lookup = self._repository.get_content_records(list(content_scores.keys()))
        ranked_content = sorted(content_scores.items(), key=lambda item: item[1], reverse=True)[:6]

        current_reads = []
        for content_id, score in ranked_content:
            record = content_lookup.get(content_id, {})
            title = record.get("title") or content_titles.get(content_id) or "Untitled"
            author = record.get("author") or content_authors.get(content_id) or ""
            summary = (record.get("summary") or "")[:220]
            current_reads.append(
                {
                    "title": title,
                    "author": author,
                    "score": round(score, 2),
                    "summary": summary,
                    "file_type": record.get("file_type"),
                }
            )

        prior_themes = [
            {
                "title": curation.get("title"),
                "summary": (curation.get("summary") or "")[:200],
                "created_at": curation.get("created_at"),
            }
            for curation in past_curations[:3]
        ]

        state = {
            "current_high_engagement_reads": current_reads,
            "recent_interactions": interactions[:8],
            "recent_reading_sessions": sessions[:8],
            "prior_curation_themes": prior_themes,
            "personalization_guidance": [
                "Weight recently read and high-engagement items strongly.",
                "Prefer complementary readings that deepen current interests.",
                "Diversify source types and avoid repeating near-duplicate picks.",
            ],
        }
        return state

    async def _build_vault_context(self, user_id: str, user_state: dict[str, Any]) -> dict[str, Any]:
        recent_notes = self._repository.list_recent_vault_notes(user_id, limit=6)
        current_reads = user_state.get("current_high_engagement_reads", [])
        prior_themes = user_state.get("prior_curation_themes", [])
        query_terms = [item.get("title", "") for item in current_reads[:3]] + [
            item.get("title", "") for item in prior_themes[:2]
        ]
        semantic_query = ", ".join(term for term in query_terms if term).strip()

        related_notes = {"results": [], "count": 0}
        if semantic_query:
            related_notes = await self._semantic_vault.search_notes(user_id, semantic_query, limit=6)

        return {
            "recent_notes": recent_notes,
            "related_notes": related_notes.get("results", []),
            "semantic_query": semantic_query,
        }

    async def _finalize_curation(
        self,
        *,
        curation_id: str,
        user_id: str,
        max_items: int,
        raw_content: str,
    ) -> dict[str, Any]:
        cleaned = raw_content.replace("```json", "").replace("```", "").strip()
        try:
            payload = json.loads(cleaned)
        except json.JSONDecodeError:
            payload = {
                "title": "Daily Curation",
                "summary": raw_content,
                "items": [],
            }

        normalized_items = self._normalize_items(payload.get("items", []), max_items)
        inserted = self._repository.insert_curation_items(curation_id, normalized_items)
        self._repository.update_curation(
            curation_id,
            {
                "title": payload.get("title") or "Daily Curation",
                "summary": payload.get("summary") or raw_content,
                "status": "ready",
            },
        )
        self._repository.insert_curation_message(
            curation_id,
            "assistant",
            payload.get("summary") or raw_content,
        )
        await self._write_daily_reflection(
            user_id=user_id,
            summary=payload.get("summary") or raw_content,
            items=normalized_items,
        )
        return {"curation_id": curation_id, "status": "created", "items_added": inserted}

    def _normalize_items(self, items: list[Any], max_items: int) -> list[dict[str, Any]]:
        normalized: list[dict[str, Any]] = []
        for item in items[:max_items]:
            if not isinstance(item, dict):
                continue
            normalized.append(
                {
                    "content_id": item.get("content_id"),
                    "external_url": item.get("external_url"),
                    "external_title": item.get("external_title"),
                    "external_author": item.get("external_author"),
                    "external_summary": item.get("external_summary"),
                    "agent_note": item.get("agent_note"),
                    "item_type": item.get("item_type") or ("content" if item.get("content_id") else "external_link"),
                }
            )
        return normalized

    def _format_assistant_content(self, content: str, tool_calls: list[Any]) -> list[dict[str, Any]]:
        blocks: list[dict[str, Any]] = []
        if content:
            blocks.append({"type": "text", "text": content})
        for tool_call in tool_calls:
            blocks.append(
                {
                    "type": "tool_use",
                    "id": tool_call.id,
                    "name": tool_call.name,
                    "input": tool_call.input,
                }
            )
        return blocks

    async def _write_daily_reflection(self, *, user_id: str, summary: str, items: list[dict[str, Any]]) -> None:
        if not user_id:
            return

        lines = [summary.strip()]
        if items:
            lines.append("")
            lines.append("## Recommended readings")
            for item in items[:6]:
                title = item.get("external_title") or item.get("content_id") or "Untitled recommendation"
                note = item.get("agent_note") or "Recommended by curator"
                lines.append(f"- **{title}** — {note}")

        await self._tools.execute(
            "append_to_daily_note",
            {
                "user_id": user_id,
                "title": "Curator Reflection",
                "body": "\n".join(lines).strip(),
                "tags": ["daily", "curator", "reading"],
            },
        )
