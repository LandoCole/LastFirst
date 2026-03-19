from __future__ import annotations

from collections.abc import Iterable
from datetime import UTC, datetime, timedelta
from typing import Any

from supabase import Client, create_client

from app.models import DailyCurationConfig, VaultProvisionRequest


class SupabaseRepository:
    def __init__(self, supabase_url: str, service_role_key: str) -> None:
        self._client: Client = create_client(supabase_url, service_role_key)

    def get_primary_vault(self, user_id: str) -> dict[str, Any] | None:
        response = (
            self._client.table("vaults")
            .select("*")
            .eq("user_id", user_id)
            .eq("is_primary", True)
            .limit(1)
            .execute()
        )
        rows = response.data or []
        return rows[0] if rows else None

    def ensure_vault(self, request: VaultProvisionRequest) -> tuple[str, bool]:
        existing = self.get_primary_vault(request.user_id) if request.is_primary else None
        if existing:
            return existing["id"], False

        response = (
            self._client.table("vaults")
            .insert(
                {
                    "user_id": request.user_id,
                    "label": request.label,
                    "provider": request.provider,
                    "connection_type": request.connection_type,
                    "status": "active",
                    "root_path": request.root_path,
                    "is_primary": request.is_primary,
                    "settings": request.settings,
                }
            )
            .select("id")
            .single()
            .execute()
        )
        return response.data["id"], True

    def start_vault_sync_run(
        self,
        *,
        vault_id: str,
        trigger_source: str,
        metadata: dict[str, Any] | None = None,
    ) -> str:
        response = (
            self._client.table("vault_sync_runs")
            .insert(
                {
                    "vault_id": vault_id,
                    "trigger_source": trigger_source,
                    "status": "running",
                    "metadata": metadata or {},
                }
            )
            .select("id")
            .single()
            .execute()
        )
        return response.data["id"]

    def complete_vault_sync_run(
        self,
        *,
        sync_run_id: str,
        status: str,
        notes_total: int,
        chunks_total: int,
        error_message: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        payload: dict[str, Any] = {
            "status": status,
            "notes_total": notes_total,
            "chunks_total": chunks_total,
            "completed_at": datetime.now(UTC).isoformat(),
        }
        if error_message:
            payload["error_message"] = error_message
        if metadata is not None:
            payload["metadata"] = metadata

        self._client.table("vault_sync_runs").update(payload).eq("id", sync_run_id).execute()

    def replace_vault_notes(
        self,
        *,
        vault_id: str,
        user_id: str,
        notes: list[dict[str, Any]],
    ) -> dict[str, str]:
        self._client.table("vault_note_chunks").delete().eq("vault_id", vault_id).execute()
        self._client.table("vault_note_links").delete().eq("vault_id", vault_id).execute()
        self._client.table("vault_notes").delete().eq("vault_id", vault_id).execute()

        if not notes:
            return {}

        payload = []
        sync_timestamp = datetime.now(UTC).isoformat()
        for note in notes:
            row = dict(note)
            row["vault_id"] = vault_id
            row["user_id"] = user_id
            row["last_synced_at"] = sync_timestamp
            payload.append(row)

        response = self._client.table("vault_notes").insert(payload).select("id, path").execute()
        rows = response.data or []
        return {row["path"]: row["id"] for row in rows if row.get("path") and row.get("id")}

    def insert_vault_links(self, links: list[dict[str, Any]]) -> int:
        if not links:
            return 0
        self._client.table("vault_note_links").insert(links).execute()
        return len(links)

    def insert_vault_chunks(self, chunks: list[dict[str, Any]]) -> int:
        if not chunks:
            return 0
        self._client.table("vault_note_chunks").insert(chunks).execute()
        return len(chunks)

    def list_vault_chunks(self, user_id: str, limit: int = 300) -> list[dict[str, Any]]:
        vault = self.get_primary_vault(user_id)
        if not vault:
            return []

        chunk_response = (
            self._client.table("vault_note_chunks")
            .select("id, note_id, chunk_index, content, token_estimate, metadata, embedding, embedding_model, embedded_at")
            .eq("vault_id", vault["id"])
            .limit(limit)
            .execute()
        )
        chunks = chunk_response.data or []
        note_ids = [chunk["note_id"] for chunk in chunks if chunk.get("note_id")]
        if not note_ids:
            return []

        note_response = (
            self._client.table("vault_notes")
            .select("id, path, title, note_type, tags, updated_at")
            .in_("id", list(dict.fromkeys(note_ids)))
            .execute()
        )
        note_rows = note_response.data or []
        note_map = {row["id"]: row for row in note_rows if row.get("id")}

        results = []
        for chunk in chunks:
            note = note_map.get(chunk.get("note_id"))
            if not note:
                continue
            payload = dict(chunk)
            payload["note"] = note
            results.append(payload)
        return results

    def update_vault_sync_state(self, vault_id: str) -> None:
        self._client.table("vaults").update(
            {
                "last_synced_at": datetime.now(UTC).isoformat(),
                "updated_at": datetime.now(UTC).isoformat(),
            }
        ).eq("id", vault_id).execute()

    def list_recent_vault_notes(self, user_id: str, limit: int = 6) -> list[dict[str, Any]]:
        vault = self.get_primary_vault(user_id)
        if not vault:
            return []

        response = (
            self._client.table("vault_notes")
            .select("id, path, title, note_type, tags, updated_at, content_markdown")
            .eq("vault_id", vault["id"])
            .order("updated_at", desc=True)
            .limit(limit)
            .execute()
        )
        return [self._summarize_vault_note(row) for row in (response.data or [])]

    def search_vault_notes(self, user_id: str, query: str, limit: int = 8) -> dict[str, Any]:
        vault = self.get_primary_vault(user_id)
        if not vault:
            return {"results": [], "count": 0}

        cleaned_query = query.strip()
        if not cleaned_query:
            return {"results": [], "count": 0}

        response = (
            self._client.table("vault_notes")
            .select("id, path, title, note_type, tags, updated_at, content_markdown")
            .eq("vault_id", vault["id"])
            .or_(
                f"title.ilike.%{cleaned_query}%,path.ilike.%{cleaned_query}%,content_markdown.ilike.%{cleaned_query}%"
            )
            .limit(limit)
            .execute()
        )
        rows = response.data or []
        return {
            "results": [self._summarize_vault_note(row) for row in rows],
            "count": len(rows),
        }

    def get_vault_note(
        self,
        *,
        user_id: str,
        note_id: str | None = None,
        path: str | None = None,
    ) -> dict[str, Any]:
        vault = self.get_primary_vault(user_id)
        if not vault:
            return {}

        query = self._client.table("vault_notes").select("*").eq("vault_id", vault["id"])
        if note_id:
            query = query.eq("id", note_id)
        elif path:
            query = query.eq("path", self._normalize_note_path(path))
        else:
            return {}

        response = query.limit(1).execute()
        rows = response.data or []
        return rows[0] if rows else {}

    def get_vault_backlinks(
        self,
        *,
        user_id: str,
        note_id: str | None = None,
        path: str | None = None,
        limit: int = 10,
    ) -> dict[str, Any]:
        note = self.get_vault_note(user_id=user_id, note_id=note_id, path=path)
        if not note:
            return {"results": [], "count": 0}

        response = (
            self._client.table("vault_note_links")
            .select("source_note_id, target_note_id, target_path, link_text")
            .eq("vault_id", note["vault_id"])
            .or_(f"target_note_id.eq.{note['id']},target_path.eq.{note['path']}")
            .limit(limit)
            .execute()
        )
        links = response.data or []
        source_ids = [link["source_note_id"] for link in links if link.get("source_note_id")]
        if not source_ids:
            return {"results": [], "count": 0}

        source_response = (
            self._client.table("vault_notes")
            .select("id, path, title, note_type, tags, updated_at, content_markdown")
            .in_("id", list(dict.fromkeys(source_ids)))
            .execute()
        )
        source_rows = source_response.data or []
        source_map = {row["id"]: row for row in source_rows}

        results = []
        for link in links:
            source_row = source_map.get(link.get("source_note_id"))
            if not source_row:
                continue
            summarized = self._summarize_vault_note(source_row)
            summarized["link_text"] = link.get("link_text")
            results.append(summarized)

        return {"results": results, "count": len(results)}

    def upsert_vault_note_graph(
        self,
        *,
        vault_id: str,
        user_id: str,
        note: dict[str, Any],
        links: list[dict[str, Any]],
        chunks: list[dict[str, Any]],
    ) -> str:
        sync_timestamp = datetime.now(UTC).isoformat()
        payload = dict(note)
        payload["vault_id"] = vault_id
        payload["user_id"] = user_id
        payload["last_synced_at"] = sync_timestamp

        response = (
            self._client.table("vault_notes")
            .upsert(payload, on_conflict="vault_id,path")
            .select("id, path")
            .execute()
        )
        rows = response.data or []
        row = rows[0] if isinstance(rows, list) and rows else rows
        note_id = row["id"]

        self._client.table("vault_note_links").delete().eq("vault_id", vault_id).eq("source_note_id", note_id).execute()
        self._client.table("vault_note_chunks").delete().eq("vault_id", vault_id).eq("note_id", note_id).execute()

        target_map = self._resolve_vault_note_paths(vault_id, [link["target_path"] for link in links])
        link_payload = [
            {
                "vault_id": vault_id,
                "source_note_id": note_id,
                "target_note_id": target_map.get(link["target_path"]),
                "target_path": link["target_path"],
                "link_text": link.get("link_text"),
            }
            for link in links
        ]
        chunk_payload = [
            {
                "vault_id": vault_id,
                "note_id": note_id,
                "chunk_index": chunk["chunk_index"],
                "content": chunk["content"],
                "token_estimate": chunk["token_estimate"],
                "metadata": chunk["metadata"],
            }
            for chunk in chunks
        ]

        self.insert_vault_links(link_payload)
        self.insert_vault_chunks(chunk_payload)
        self.update_vault_sync_state(vault_id)
        return note_id

    def list_daily_configs(self, user_id: str | None = None, max_users: int | None = None) -> list[DailyCurationConfig]:
        query = self._client.table("daily_curation_config").select("*").eq("enabled", True)
        if user_id:
            query = query.eq("user_id", user_id)
        if max_users:
            query = query.limit(max_users)
        response = query.execute()
        return [DailyCurationConfig.model_validate(row) for row in (response.data or [])]

    def has_daily_curation_today(self, user_id: str, now: datetime | None = None) -> bool:
        moment = now or datetime.now(UTC)
        start = moment.replace(hour=0, minute=0, second=0, microsecond=0)
        end = start + timedelta(days=1)
        response = (
            self._client.table("curations")
            .select("id")
            .eq("user_id", user_id)
            .eq("type", "daily")
            .gte("created_at", start.isoformat())
            .lt("created_at", end.isoformat())
            .limit(1)
            .execute()
        )
        return bool(response.data)

    def create_daily_curation(self, user_id: str) -> str:
        expires_at = (datetime.now(UTC) + timedelta(days=1)).isoformat()
        response = (
            self._client.table("curations")
            .insert(
                {
                    "user_id": user_id,
                    "type": "daily",
                    "title": "Daily Curation",
                    "status": "researching",
                    "complexity": "moderate",
                    "agent_count": 1,
                    "expires_at": expires_at,
                }
            )
            .select("id")
            .single()
            .execute()
        )
        return response.data["id"]

    def update_curation(self, curation_id: str, values: dict[str, Any]) -> None:
        self._client.table("curations").update(values).eq("id", curation_id).execute()

    def insert_curation_message(self, curation_id: str, role: str, content: str) -> None:
        self._client.table("curation_messages").insert(
            {
                "curation_id": curation_id,
                "role": role,
                "content": content,
            }
        ).execute()

    def insert_curation_items(self, curation_id: str, items: Iterable[dict[str, Any]]) -> int:
        payload = []
        for index, item in enumerate(items):
            row = {
                "curation_id": curation_id,
                "position": index,
                "item_type": item.get("item_type") or "external_link",
                "agent_note": item.get("agent_note"),
            }
            if item.get("content_id"):
                row["content_id"] = item["content_id"]
            if item.get("external_url"):
                row["external_url"] = item["external_url"]
            if item.get("external_title"):
                row["external_title"] = item["external_title"]
            if item.get("external_author"):
                row["external_author"] = item["external_author"]
            if item.get("external_summary"):
                row["external_summary"] = item["external_summary"]
            payload.append(row)

        if not payload:
            return 0

        self._client.table("curation_items").insert(payload).execute()
        return len(payload)

    def mark_daily_generated(self, config_id: str) -> None:
        self._client.table("daily_curation_config").update(
            {"last_generated_at": datetime.now(UTC).isoformat()}
        ).eq("id", config_id).execute()

    def search_content(self, query: str, limit: int = 10) -> dict[str, Any]:
        response = (
            self._client.table("content")
            .select("id, title, author, summary, file_type, is_available")
            .or_(f"title.ilike.%{query}%,author.ilike.%{query}%,summary.ilike.%{query}%")
            .eq("is_available", True)
            .limit(limit)
            .execute()
        )
        results = response.data or []
        return {"results": results, "count": len(results)}

    def get_content_details(self, content_id: str) -> dict[str, Any]:
        response = self._client.table("content").select("*").eq("id", content_id).single().execute()
        return response.data or {}

    def get_content_records(self, content_ids: list[str]) -> dict[str, dict[str, Any]]:
        ids = list(dict.fromkeys(content_ids))
        if not ids:
            return {}
        response = self._client.table("content").select("*").in_("id", ids).execute()
        data = response.data or []
        return {row["id"]: row for row in data}

    def get_user_reading_history(self, user_id: str, limit: int = 20) -> dict[str, Any]:
        interactions = (
            self._client.table("interactions")
            .select("kind, content:content_id(id, title, author, file_type, summary), created_at")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        ).data or []

        sessions = (
            self._client.table("reading_sessions")
            .select("content_id, duration_seconds, pages_read, started_at")
            .eq("user_id", user_id)
            .order("started_at", desc=True)
            .limit(limit)
            .execute()
        ).data or []

        curations = (
            self._client.table("curations")
            .select("id, title, prompt, summary, status, created_at")
            .eq("user_id", user_id)
            .eq("status", "ready")
            .order("created_at", desc=True)
            .limit(5)
            .execute()
        ).data or []

        return {
            "interactions": interactions,
            "reading_sessions": sessions,
            "past_curations": curations,
        }

    def upsert_web_content(
        self,
        *,
        url: str,
        title: str,
        author: str | None,
        markdown: str,
        html: str,
        metadata: dict[str, Any],
    ) -> dict[str, Any]:
        word_count = len([word for word in markdown.split() if word])
        estimated_read_minutes = max(1, round(word_count / 238))
        file_type = "pdf" if url.lower().endswith(".pdf") else "web"
        response = (
            self._client.table("content")
            .upsert(
                {
                    "source_type": "web",
                    "source_url": url,
                    "title": title,
                    "author": author,
                    "summary": markdown[:500],
                    "body_text": markdown,
                    "body_html": html,
                    "language": metadata.get("language") or "en",
                    "word_count": word_count,
                    "estimated_read_minutes": estimated_read_minutes,
                    "file_type": file_type,
                    "is_available": True,
                    "metadata": metadata,
                },
                on_conflict="source_url",
            )
            .execute()
        )
        rows = response.data or []
        if isinstance(rows, dict):
            row = rows
        else:
            row = rows[0] if rows else {}
        return row

    def _resolve_vault_note_paths(self, vault_id: str, paths: list[str]) -> dict[str, str]:
        normalized_paths = [self._normalize_note_path(path) for path in paths if path]
        if not normalized_paths:
            return {}

        response = (
            self._client.table("vault_notes")
            .select("id, path")
            .eq("vault_id", vault_id)
            .in_("path", list(dict.fromkeys(normalized_paths)))
            .execute()
        )
        rows = response.data or []
        return {row["path"]: row["id"] for row in rows if row.get("path") and row.get("id")}

    def _summarize_vault_note(self, row: dict[str, Any]) -> dict[str, Any]:
        content = row.get("content_markdown") or ""
        return {
            "id": row.get("id"),
            "path": row.get("path"),
            "title": row.get("title"),
            "note_type": row.get("note_type"),
            "tags": row.get("tags") or [],
            "updated_at": row.get("updated_at"),
            "excerpt": content[:280],
        }

    def _normalize_note_path(self, path: str) -> str:
        cleaned = path.strip().replace("\\", "/").lstrip("./")
        if not cleaned.endswith(".md"):
            cleaned = f"{cleaned}.md"
        return cleaned
