from __future__ import annotations

import math
import re
from typing import Any

from app.services.embeddings import EmbeddingService
from app.services.supabase_repository import SupabaseRepository

TOKEN_PATTERN = re.compile(r"[A-Za-z0-9_\-]+")


class SemanticVaultService:
    def __init__(
        self,
        repository: SupabaseRepository,
        embedding_service: EmbeddingService,
        candidate_limit: int = 300,
    ) -> None:
        self._repository = repository
        self._embedding_service = embedding_service
        self._candidate_limit = candidate_limit

    async def search_notes(self, user_id: str, query: str, limit: int = 8) -> dict[str, Any]:
        lexical = self._repository.search_vault_notes(user_id, query, limit=max(limit, 8))
        if not self._embedding_service.enabled:
            return lexical

        query_embedding = (await self._embedding_service.embed_texts([query]))[0]
        if not query_embedding:
            return lexical

        candidate_chunks = self._repository.list_vault_chunks(user_id, limit=self._candidate_limit)
        if not candidate_chunks:
            return lexical

        note_scores: dict[str, dict[str, Any]] = {}
        for chunk in candidate_chunks:
            embedding = chunk.get("embedding")
            note = chunk.get("note")
            if not isinstance(embedding, list) or not note:
                continue

            semantic_score = cosine_similarity(query_embedding, [float(v) for v in embedding])
            lexical_score = lexical_overlap(query, f"{note.get('title', '')} {chunk.get('content', '')}")
            combined = semantic_score + (lexical_score * 0.08)

            note_id = str(note.get("id") or "")
            if not note_id:
                continue

            existing = note_scores.get(note_id)
            candidate = {
                "id": note.get("id"),
                "path": note.get("path"),
                "title": note.get("title"),
                "note_type": note.get("note_type"),
                "tags": note.get("tags") or [],
                "updated_at": note.get("updated_at"),
                "excerpt": chunk.get("content", "")[:280],
                "score": round(combined, 4),
            }
            if existing is None or combined > existing["score"]:
                note_scores[note_id] = candidate

        ranked = sorted(note_scores.values(), key=lambda item: item["score"], reverse=True)
        results = ranked[:limit]

        if not results:
            return lexical

        lexical_by_id = {str(item.get("id")): item for item in lexical.get("results", [])}
        for result in results:
            lexical_match = lexical_by_id.get(str(result.get("id")))
            if lexical_match and not result.get("excerpt"):
                result["excerpt"] = lexical_match.get("excerpt")

        return {"results": results, "count": len(results)}



def cosine_similarity(left: list[float], right: list[float]) -> float:
    if not left or not right or len(left) != len(right):
        return 0.0
    numerator = sum(a * b for a, b in zip(left, right))
    left_norm = math.sqrt(sum(a * a for a in left))
    right_norm = math.sqrt(sum(b * b for b in right))
    if left_norm == 0 or right_norm == 0:
        return 0.0
    return numerator / (left_norm * right_norm)



def lexical_overlap(query: str, text: str) -> float:
    query_tokens = set(TOKEN_PATTERN.findall(query.lower()))
    if not query_tokens:
        return 0.0
    text_tokens = set(TOKEN_PATTERN.findall(text.lower()))
    if not text_tokens:
        return 0.0
    overlap = len(query_tokens & text_tokens)
    return overlap / len(query_tokens)
