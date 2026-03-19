from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    agent_service_internal_key: str
    supabase_url: str
    supabase_service_role_key: str
    anthropic_api_key: str
    firecrawl_api_key: str | None = None
    openai_api_key: str | None = None
    app_env: str = "development"
    agent_default_model: str = "claude-sonnet-4-20250514"
    agent_default_max_items: int = 5
    agent_default_history_limit: int = 30
    embedding_model: str = "text-embedding-3-small"
    semantic_search_candidate_limit: int = 300

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
