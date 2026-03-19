from __future__ import annotations

from typing import Any

import httpx


class EmbeddingService:
    def __init__(self, api_key: str | None, model: str) -> None:
        self._api_key = api_key
        self._model = model

    @property
    def enabled(self) -> bool:
        return bool(self._api_key)

    @property
    def model(self) -> str:
        return self._model

    async def embed_texts(self, texts: list[str]) -> list[list[float] | None]:
        if not texts:
            return []
        if not self._api_key:
            return [None for _ in texts]

        async with httpx.AsyncClient(timeout=90.0) as client:
            response = await client.post(
                "https://api.openai.com/v1/embeddings",
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {self._api_key}",
                },
                json={
                    "model": self._model,
                    "input": texts,
                },
            )
            response.raise_for_status()
            payload = response.json()

        data = payload.get("data", [])
        vectors: list[list[float] | None] = [None for _ in texts]
        for item in data:
            index = int(item.get("index", 0))
            embedding = item.get("embedding")
            if 0 <= index < len(vectors) and isinstance(embedding, list):
                vectors[index] = [float(value) for value in embedding]
        return vectors
