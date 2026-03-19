from __future__ import annotations

from typing import Any

import httpx

from app.models import NormalizedLLMResponse, ToolCall


class AnthropicService:
    def __init__(self, api_key: str) -> None:
        self._api_key = api_key

    async def call_with_tools(
        self,
        *,
        system_prompt: str,
        messages: list[dict[str, Any]],
        model: str,
        tools: list[dict[str, Any]] | None = None,
        max_tokens: int = 4096,
    ) -> NormalizedLLMResponse:
        payload: dict[str, Any] = {
            "model": model,
            "max_tokens": max_tokens,
            "system": system_prompt,
            "messages": messages,
        }
        if tools:
            payload["tools"] = tools

        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(
                "https://api.anthropic.com/v1/messages",
                headers={
                    "Content-Type": "application/json",
                    "x-api-key": self._api_key,
                    "anthropic-version": "2023-06-01",
                },
                json=payload,
            )
            response.raise_for_status()
            data = response.json()

        content_parts: list[str] = []
        tool_calls: list[ToolCall] = []
        for block in data.get("content", []):
            if block.get("type") == "text":
                content_parts.append(block.get("text", ""))
            elif block.get("type") == "tool_use":
                tool_calls.append(
                    ToolCall(
                        id=block["id"],
                        name=block["name"],
                        input=block.get("input", {}),
                    )
                )

        return NormalizedLLMResponse(
            content="".join(content_parts),
            tool_calls=tool_calls,
            stop_reason=data.get("stop_reason", "end_turn"),
            usage=data.get("usage"),
        )
