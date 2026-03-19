from __future__ import annotations

import json
import re
from datetime import UTC, datetime
from typing import Any

import httpx

from app.models import VaultNoteInput
from app.services.obsidian_parser import ObsidianParser
from app.services.firecrawl import FirecrawlService
from app.services.semantic_vault import SemanticVaultService
from app.services.supabase_repository import SupabaseRepository

TOOL_DEFINITIONS: list[dict[str, Any]] = [
    {
        "name": "search_content",
        "description": "Search the internal content library for books, articles, and papers. Returns titles, authors, summaries, and IDs.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query"},
                "limit": {"type": "number", "description": "Max results (default 10)"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "get_content_details",
        "description": "Get full details for a specific content item by ID, including summary, file type, and availability.",
        "input_schema": {
            "type": "object",
            "properties": {
                "content_id": {"type": "string", "description": "UUID of the content item"},
            },
            "required": ["content_id"],
        },
    },
    {
        "name": "search_web",
        "description": "Search the web for books, articles, papers, or other reading material from reliable sources.",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query"},
                "num_results": {"type": "number", "description": "Number of results (default 5)"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "fetch_url",
        "description": "Fetch and extract content from a URL. Returns title, author, and text content.",
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "URL to fetch"},
            },
            "required": ["url"],
        },
    },
    {
        "name": "get_user_reading_history",
        "description": "Get the user's reading history including past interactions, bookmarks, and reading sessions.",
        "input_schema": {
            "type": "object",
            "properties": {
                "user_id": {"type": "string", "description": "User UUID"},
                "limit": {"type": "number", "description": "Max results (default 20)"},
            },
            "required": ["user_id"],
        },
    },
    {
        "name": "ingest_url",
        "description": "Ingest a URL into the content library, preserving readable body text when available.",
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "URL to ingest"},
                "title": {"type": "string", "description": "Title override"},
                "author": {"type": "string", "description": "Author override"},
            },
            "required": ["url"],
        },
    },
    {
        "name": "search_vault_notes",
        "description": "Search the user's knowledge graph notes for relevant concepts, summaries, and context.",
        "input_schema": {
            "type": "object",
            "properties": {
                "user_id": {"type": "string", "description": "User UUID"},
                "query": {"type": "string", "description": "Vault search query"},
                "limit": {"type": "number", "description": "Max results (default 8)"},
            },
            "required": ["user_id", "query"],
        },
    },
    {
        "name": "get_vault_note",
        "description": "Read a specific knowledge-graph note by note ID or path.",
        "input_schema": {
            "type": "object",
            "properties": {
                "user_id": {"type": "string", "description": "User UUID"},
                "note_id": {"type": "string", "description": "Vault note UUID"},
                "path": {"type": "string", "description": "Vault note path"},
            },
            "required": ["user_id"],
        },
    },
    {
        "name": "get_vault_backlinks",
        "description": "Get notes that link to a given vault note to understand surrounding context.",
        "input_schema": {
            "type": "object",
            "properties": {
                "user_id": {"type": "string", "description": "User UUID"},
                "note_id": {"type": "string", "description": "Vault note UUID"},
                "path": {"type": "string", "description": "Vault note path"},
                "limit": {"type": "number", "description": "Max backlinks (default 10)"},
            },
            "required": ["user_id"],
        },
    },
    {
        "name": "append_to_daily_note",
        "description": "Create or update today's daily note with agent reflections, summaries, and recommendations.",
        "input_schema": {
            "type": "object",
            "properties": {
                "user_id": {"type": "string", "description": "User UUID"},
                "title": {"type": "string", "description": "Heading or title for the note"},
                "body": {"type": "string", "description": "Markdown content to store"},
                "tags": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Tags for the note",
                },
            },
            "required": ["user_id", "body"],
        },
    },
]


class ToolExecutor:
    def __init__(
        self,
        repository: SupabaseRepository,
        firecrawl: FirecrawlService,
        semantic_vault: SemanticVaultService | None = None,
    ) -> None:
        self._repository = repository
        self._firecrawl = firecrawl
        self._parser = ObsidianParser()
        self._semantic_vault = semantic_vault

    async def execute(self, tool_name: str, input_data: dict[str, Any]) -> str:
        if tool_name == "search_content":
            payload = self._repository.search_content(
                query=str(input_data.get("query", "")),
                limit=int(input_data.get("limit", 10)),
            )
            return json.dumps(payload)

        if tool_name == "get_content_details":
            payload = self._repository.get_content_details(str(input_data.get("content_id", "")))
            return json.dumps(payload)

        if tool_name == "search_web":
            payload = await self._firecrawl.search(
                query=str(input_data.get("query", "")),
                limit=int(input_data.get("num_results", 5)),
            )
            return json.dumps(payload)

        if tool_name == "fetch_url":
            payload = await self._fetch_url(str(input_data.get("url", "")))
            return json.dumps(payload)

        if tool_name == "get_user_reading_history":
            payload = self._repository.get_user_reading_history(
                user_id=str(input_data.get("user_id", "")),
                limit=int(input_data.get("limit", 20)),
            )
            return json.dumps(payload)

        if tool_name == "ingest_url":
            payload = await self._ingest_url(
                url=str(input_data.get("url", "")),
                title=input_data.get("title"),
                author=input_data.get("author"),
            )
            return json.dumps(payload)

        if tool_name == "search_vault_notes":
            if self._semantic_vault is not None:
                payload = await self._semantic_vault.search_notes(
                    user_id=str(input_data.get("user_id", "")),
                    query=str(input_data.get("query", "")),
                    limit=int(input_data.get("limit", 8)),
                )
            else:
                payload = self._repository.search_vault_notes(
                    user_id=str(input_data.get("user_id", "")),
                    query=str(input_data.get("query", "")),
                    limit=int(input_data.get("limit", 8)),
                )
            return json.dumps(payload)

        if tool_name == "get_vault_note":
            payload = self._repository.get_vault_note(
                user_id=str(input_data.get("user_id", "")),
                note_id=str(input_data.get("note_id", "")) or None,
                path=str(input_data.get("path", "")) or None,
            )
            return json.dumps(payload)

        if tool_name == "get_vault_backlinks":
            payload = self._repository.get_vault_backlinks(
                user_id=str(input_data.get("user_id", "")),
                note_id=str(input_data.get("note_id", "")) or None,
                path=str(input_data.get("path", "")) or None,
                limit=int(input_data.get("limit", 10)),
            )
            return json.dumps(payload)

        if tool_name == "append_to_daily_note":
            payload = self._append_to_daily_note(
                user_id=str(input_data.get("user_id", "")),
                title=str(input_data.get("title", "") or "Daily Reflection"),
                body=str(input_data.get("body", "")),
                tags=input_data.get("tags") if isinstance(input_data.get("tags"), list) else None,
            )
            return json.dumps(payload)

        return json.dumps({"error": f"Unknown tool: {tool_name}"})

    async def _fetch_url(self, url: str) -> dict[str, Any]:
        if self._firecrawl.enabled:
            try:
                document = await self._firecrawl.scrape(url, ["markdown", "html"])
                metadata = document.get("metadata", {})
                markdown = document.get("markdown", "")
                return {
                    "title": metadata.get("title", ""),
                    "author": extract_author(metadata),
                    "content": markdown[:4000],
                    "url": url,
                    "readable": len(markdown) > 500,
                }
            except Exception as exc:
                return {"error": f"Failed to fetch URL: {exc}"}

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.get(url, headers={"User-Agent": "LastFirst-Agent/1.0"})
                response.raise_for_status()
                text = response.text
        except Exception as exc:
            return {"error": f"Failed to fetch URL: {exc}"}

        title_match = re.search(r"<title[^>]*>(.*?)</title>", text, re.IGNORECASE | re.DOTALL)
        return {
            "title": title_match.group(1).strip() if title_match else "",
            "content": re.sub(r"<[^>]*>", "", text)[:4000],
            "url": url,
            "readable": True,
        }

    async def _ingest_url(self, url: str, title: Any = None, author: Any = None) -> dict[str, Any]:
        if not self._firecrawl.enabled:
            return {"error": "FIRECRAWL_API_KEY not set"}

        try:
            document = await self._firecrawl.scrape(url, ["markdown", "html"])
        except Exception as exc:
            return {"error": f"Ingest failed: {exc}"}

        metadata = document.get("metadata", {})
        markdown = document.get("markdown", "")
        html = document.get("html", "")
        chosen_title = str(title or metadata.get("title") or "")
        chosen_author = str(author or extract_author(metadata) or "") or None
        row = self._repository.upsert_web_content(
            url=url,
            title=chosen_title,
            author=chosen_author,
            markdown=markdown,
            html=html,
            metadata=metadata,
        )
        content_id = row.get("id") if isinstance(row, dict) else None
        return {
            "success": True,
            "content_id": content_id,
            "title": chosen_title,
            "author": chosen_author,
            "content_preview": markdown[:500],
            "url": url,
        }

    def _append_to_daily_note(
        self,
        *,
        user_id: str,
        title: str,
        body: str,
        tags: list[Any] | None = None,
    ) -> dict[str, Any]:
        vault = self._repository.get_primary_vault(user_id)
        if not vault:
            return {"error": "No primary vault available for user"}

        now = datetime.now(UTC)
        path = f"Daily/{now.strftime('%Y-%m-%d')}.md"
        frontmatter = {
            "title": title,
            "date": now.date().isoformat(),
            "agent_generated": True,
        }
        normalized_tags = [str(tag).strip() for tag in (tags or []) if str(tag).strip()]
        if "daily" not in normalized_tags:
            normalized_tags.append("daily")
        if "agent" not in normalized_tags:
            normalized_tags.append("agent")

        existing_note = self._repository.get_vault_note(user_id=user_id, path=path)
        existing_content = (existing_note.get("content_markdown") or "").strip() if existing_note else ""
        section_heading = now.strftime("%I:%M %p").lstrip("0")
        new_section = f"## {section_heading}\n\n{body.strip()}\n"

        if existing_content:
            content_markdown = f"{existing_content}\n\n{new_section}"
        else:
            content_markdown = f"# {title}\n\n{new_section}"

        parsed_notes, pending_links, pending_chunks = self._parser.parse_notes(
            [
                VaultNoteInput(
                    path=path,
                    content_markdown=content_markdown,
                    title=title,
                    note_type="daily_note",
                    tags=sorted(set(normalized_tags)),
                    frontmatter=frontmatter,
                )
            ]
        )
        note = parsed_notes[0]
        note_id = self._repository.upsert_vault_note_graph(
            vault_id=vault["id"],
            user_id=user_id,
            note=note,
            links=pending_links,
            chunks=pending_chunks,
        )
        return {"success": True, "note_id": note_id, "path": path, "title": title}


def extract_author(metadata: dict[str, Any]) -> str:
    return str(
        metadata.get("author")
        or metadata.get("og:author")
        or metadata.get("article:author")
        or metadata.get("dc.creator")
        or metadata.get("twitter:creator")
        or metadata.get("ogAuthor")
        or ""
    )
