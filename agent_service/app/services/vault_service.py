from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from app.models import (
    VaultImportRequest,
    VaultImportResponse,
    VaultProvisionRequest,
    VaultProvisionResponse,
)
from app.services.embeddings import EmbeddingService
from app.services.obsidian_parser import ObsidianParser
from app.services.supabase_repository import SupabaseRepository


class VaultService:
    def __init__(self, repository: SupabaseRepository, embedding_service: EmbeddingService) -> None:
        self._repository = repository
        self._parser = ObsidianParser()
        self._embedding_service = embedding_service

    async def provision_vault(self, request: VaultProvisionRequest) -> VaultProvisionResponse:
        vault_id, created = self._repository.ensure_vault(request)
        return VaultProvisionResponse(
            vault_id=vault_id,
            created=created,
            status="active",
        )

    async def import_notes(self, request: VaultImportRequest) -> VaultImportResponse:
        vault_id = request.vault_id
        created = False
        if not vault_id:
            vault_id, created = self._repository.ensure_vault(
                VaultProvisionRequest(
                    user_id=request.user_id,
                    label=request.label or "Knowledge Graph",
                    provider="lastfirst_managed",
                    connection_type="managed",
                    is_primary=True,
                    settings={},
                )
            )

        sync_run_id = self._repository.start_vault_sync_run(
            vault_id=vault_id,
            trigger_source=request.trigger_source,
            metadata={"requested_notes": len(request.notes), "created_vault": created},
        )

        try:
            parsed_notes, pending_links, pending_chunks = self._parser.parse_notes(request.notes)
            note_ids_by_path = self._repository.replace_vault_notes(
                vault_id=vault_id,
                user_id=request.user_id,
                notes=parsed_notes,
            )

            links = self._materialize_links(vault_id, pending_links, note_ids_by_path)
            chunks = self._materialize_chunks(vault_id, pending_chunks, note_ids_by_path)
            chunks = await self._attach_embeddings(chunks)
            links_indexed = self._repository.insert_vault_links(links)
            chunks_indexed = self._repository.insert_vault_chunks(chunks)
            self._repository.update_vault_sync_state(vault_id)
            self._repository.complete_vault_sync_run(
                sync_run_id=sync_run_id,
                status="completed",
                notes_total=len(parsed_notes),
                chunks_total=chunks_indexed,
                metadata={
                    "links_indexed": links_indexed,
                    "embedded_chunks": len([chunk for chunk in chunks if chunk.get("embedding")]),
                    "embedding_model": self._embedding_service.model if self._embedding_service.enabled else None,
                },
            )
            return VaultImportResponse(
                vault_id=vault_id,
                sync_run_id=sync_run_id,
                notes_indexed=len(parsed_notes),
                chunks_indexed=chunks_indexed,
                links_indexed=links_indexed,
            )
        except Exception as exc:
            self._repository.complete_vault_sync_run(
                sync_run_id=sync_run_id,
                status="error",
                notes_total=0,
                chunks_total=0,
                error_message=str(exc),
            )
            raise

    def _materialize_links(
        self,
        vault_id: str,
        pending_links: list[dict[str, Any]],
        note_ids_by_path: dict[str, str],
    ) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        for link in pending_links:
            source_id = note_ids_by_path.get(link["source_path"])
            if not source_id:
                continue
            target_id = note_ids_by_path.get(link["target_path"])
            rows.append(
                {
                    "vault_id": vault_id,
                    "source_note_id": source_id,
                    "target_note_id": target_id,
                    "target_path": link["target_path"],
                    "link_text": link.get("link_text"),
                }
            )
        return rows

    async def _attach_embeddings(self, chunks: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not chunks or not self._embedding_service.enabled:
            return chunks

        texts = [chunk["content"] for chunk in chunks]
        vectors = await self._embedding_service.embed_texts(texts)
        embedded_at = datetime.now(UTC).isoformat()

        enriched: list[dict[str, Any]] = []
        for chunk, vector in zip(chunks, vectors):
            row = dict(chunk)
            if vector is not None:
                row["embedding"] = vector
                row["embedding_model"] = self._embedding_service.model
                row["embedded_at"] = embedded_at
            enriched.append(row)
        return enriched

    def _materialize_chunks(
        self,
        vault_id: str,
        pending_chunks: list[dict[str, Any]],
        note_ids_by_path: dict[str, str],
    ) -> list[dict[str, Any]]:
        rows: list[dict[str, Any]] = []
        for chunk in pending_chunks:
            note_id = note_ids_by_path.get(chunk["path"])
            if not note_id:
                continue
            rows.append(
                {
                    "vault_id": vault_id,
                    "note_id": note_id,
                    "chunk_index": chunk["chunk_index"],
                    "content": chunk["content"],
                    "token_estimate": chunk["token_estimate"],
                    "metadata": chunk["metadata"],
                }
            )
        return rows
