from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class DailyRunRequest(BaseModel):
    user_id: str | None = None
    max_users: int | None = Field(default=None, ge=1, le=500)
    dry_run: bool = False


class DailyRunResponse(BaseModel):
    ok: bool = True
    processed_users: int
    created_curations: int
    skipped_users: int
    results: list[dict[str, Any]]


class DailyCurationConfig(BaseModel):
    id: str
    user_id: str
    enabled: bool = True
    generation_hour: int = 6
    max_items: int = 5
    last_generated_at: str | None = None


class VaultProvisionRequest(BaseModel):
    user_id: str
    label: str = "Knowledge Graph"
    provider: str = "lastfirst_managed"
    connection_type: str = "managed"
    root_path: str | None = None
    is_primary: bool = True
    settings: dict[str, Any] = Field(default_factory=dict)


class VaultProvisionResponse(BaseModel):
    vault_id: str
    created: bool
    status: str


class VaultNoteInput(BaseModel):
    path: str
    content_markdown: str
    title: str | None = None
    note_type: str = "note"
    tags: list[str] = Field(default_factory=list)
    frontmatter: dict[str, Any] = Field(default_factory=dict)


class VaultImportRequest(BaseModel):
    user_id: str
    vault_id: str | None = None
    label: str | None = None
    trigger_source: str = "manual"
    notes: list[VaultNoteInput] = Field(default_factory=list)


class VaultImportResponse(BaseModel):
    ok: bool = True
    vault_id: str
    sync_run_id: str
    notes_indexed: int
    chunks_indexed: int
    links_indexed: int


class ToolCall(BaseModel):
    id: str
    name: str
    input: dict[str, Any]


class NormalizedLLMResponse(BaseModel):
    content: str
    tool_calls: list[ToolCall]
    stop_reason: str
    usage: dict[str, int] | None = None


class Finding(BaseModel):
    source: str
    title: str
    relevance_note: str = ""
    confidence: float = 0.5
    content_id: str | None = None
    url: str | None = None
    author: str | None = None
    summary: str | None = None


# --- Curator Chat Models ---


class CuratorChatRequest(BaseModel):
    curation_id: str | None = None
    message: str
    user_id: str | None = None
    model: str | None = None


class CuratorChatResponse(BaseModel):
    curation_id: str
    response: str | None = None
    items_added: int | None = None
    complexity: str | None = None
    agent_count: int | None = None


class ClassificationResult(BaseModel):
    complexity: str = "simple"
    subqueries: list[dict[str, str]] = Field(default_factory=list)
    reasoning: str = ""


class SubagentResult(BaseModel):
    findings: list[Finding] = Field(default_factory=list)
    tokens_used: int = 0
