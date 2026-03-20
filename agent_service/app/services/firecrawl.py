from __future__ import annotations

from typing import Any

import httpx


class FirecrawlService:
    def __init__(self, api_key: str | None) -> None:
        self._api_key = api_key

    @property
    def enabled(self) -> bool:
        return bool(self._api_key)

    async def search(self, query: str, limit: int = 5) -> dict[str, Any]:
        if not self._api_key:
            return {"results": [], "count": 0, "error": "FIRECRAWL_API_KEY not set"}

        try:
            async with httpx.AsyncClient(timeout=45.0) as client:
                response = await client.post(
                    "https://api.firecrawl.dev/v2/search",
                    headers={
                        "Content-Type": "application/json",
                        "Authorization": f"Bearer {self._api_key}",
                    },
                    json={"query": query, "limit": limit},
                )
                response.raise_for_status()
                payload = response.json()
        except Exception as exc:
            return {"results": [], "count": 0, "error": f"Web search failed: {exc}"}

        results = [
            {
                "title": item.get("title", ""),
                "url": item.get("url", ""),
                "snippet": item.get("description", ""),
            }
            for item in payload.get("data", [])
        ]
        return {"results": results, "count": len(results)}

    async def scrape(self, url: str, formats: list[str]) -> dict[str, Any]:
        if not self._api_key:
            raise RuntimeError("FIRECRAWL_API_KEY not set")

        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                "https://api.firecrawl.dev/v1/scrape",
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {self._api_key}",
                },
                json={"url": url, "formats": formats},
            )
            response.raise_for_status()
            return response.json().get("data", {})
