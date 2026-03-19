from __future__ import annotations

from fastapi import Depends, FastAPI, Header, HTTPException, status

from app.config import Settings, get_settings
from app.models import (
    CuratorChatRequest,
    CuratorChatResponse,
    DailyRunRequest,
    DailyRunResponse,
    VaultImportRequest,
    VaultImportResponse,
    VaultProvisionRequest,
    VaultProvisionResponse,
)
from app.services.anthropic_client import AnthropicService
from app.services.curator_chat import CuratorChatService
from app.services.daily_curator import DailyCuratorService
from app.services.embeddings import EmbeddingService
from app.services.firecrawl import FirecrawlService
from app.services.semantic_vault import SemanticVaultService
from app.services.supabase_repository import SupabaseRepository
from app.services.vault_service import VaultService

app = FastAPI(title="LastFirst Agent Service", version="0.1.0")


def require_internal_key(
    x_agent_service_key: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
) -> None:
    if x_agent_service_key != settings.agent_service_internal_key:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid internal key")


def get_daily_curator(settings: Settings = Depends(get_settings)) -> DailyCuratorService:
    repository = SupabaseRepository(settings.supabase_url, settings.supabase_service_role_key)
    anthropic = AnthropicService(settings.anthropic_api_key)
    firecrawl = FirecrawlService(settings.firecrawl_api_key)
    embedding_service = EmbeddingService(settings.openai_api_key, settings.embedding_model)
    semantic_vault = SemanticVaultService(
        repository=repository,
        embedding_service=embedding_service,
        candidate_limit=settings.semantic_search_candidate_limit,
    )
    return DailyCuratorService(
        repository=repository,
        anthropic=anthropic,
        firecrawl=firecrawl,
        semantic_vault=semantic_vault,
        settings=settings,
    )


def get_curator_chat(settings: Settings = Depends(get_settings)) -> CuratorChatService:
    repository = SupabaseRepository(settings.supabase_url, settings.supabase_service_role_key)
    anthropic = AnthropicService(settings.anthropic_api_key)
    firecrawl = FirecrawlService(settings.firecrawl_api_key)
    embedding_service = EmbeddingService(settings.openai_api_key, settings.embedding_model)
    semantic_vault = SemanticVaultService(
        repository=repository,
        embedding_service=embedding_service,
        candidate_limit=settings.semantic_search_candidate_limit,
    )
    return CuratorChatService(
        repository=repository,
        anthropic=anthropic,
        firecrawl=firecrawl,
        semantic_vault=semantic_vault,
        settings=settings,
    )


def get_vault_service(settings: Settings = Depends(get_settings)) -> VaultService:
    repository = SupabaseRepository(settings.supabase_url, settings.supabase_service_role_key)
    embedding_service = EmbeddingService(settings.openai_api_key, settings.embedding_model)
    return VaultService(repository, embedding_service)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/internal/daily-curations/run", response_model=DailyRunResponse, dependencies=[Depends(require_internal_key)])
async def run_daily_curations(
    request: DailyRunRequest,
    curator: DailyCuratorService = Depends(get_daily_curator),
) -> DailyRunResponse:
    return await curator.run(request)


@app.post("/internal/curator-chat", response_model=CuratorChatResponse, dependencies=[Depends(require_internal_key)])
async def curator_chat(
    request: CuratorChatRequest,
    chat_service: CuratorChatService = Depends(get_curator_chat),
) -> CuratorChatResponse:
    return await chat_service.handle(request)


@app.post("/internal/vaults/provision", response_model=VaultProvisionResponse, dependencies=[Depends(require_internal_key)])
async def provision_vault(
    request: VaultProvisionRequest,
    vault_service: VaultService = Depends(get_vault_service),
) -> VaultProvisionResponse:
    return await vault_service.provision_vault(request)


@app.post("/internal/vaults/import", response_model=VaultImportResponse, dependencies=[Depends(require_internal_key)])
async def import_vault_notes(
    request: VaultImportRequest,
    vault_service: VaultService = Depends(get_vault_service),
) -> VaultImportResponse:
    return await vault_service.import_notes(request)
