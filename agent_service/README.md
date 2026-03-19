# LastFirst Agent Service

This FastAPI service is the first external agent runtime for LastFirst. It currently owns daily-curation orchestration and is designed to sit beside Supabase rather than replace it.

## Responsibilities

- verify internal service requests
- orchestrate daily curator runs
- provision and index per-user vaults
- parse Obsidian-style markdown notes, frontmatter, tags, and wikilinks
- assemble weighted user-reading context
- call Anthropic with tool use
- search and scrape the web via Firecrawl
- write curation state and items back to Supabase

## Supabase relationship

Supabase remains the system of record for:

- auth and JWT issuance
- `curations`
- `curation_items`
- `curation_messages`
- `agent_tasks`
- future memory tables

The Supabase `curator-daily` edge function can now delegate to this service when both of these environment variables are configured in the function runtime:

- `AGENT_SERVICE_URL`
- `AGENT_SERVICE_INTERNAL_KEY`

## Endpoints

- `GET /health`
- `POST /internal/daily-curations/run`
- `POST /internal/vaults/provision`
- `POST /internal/vaults/import`

### Internal daily run request

```json
{
  "user_id": null,
  "max_users": null,
  "dry_run": false
}
```

The request must include:

- header `X-Agent-Service-Key: <AGENT_SERVICE_INTERNAL_KEY>`

## Vault foundation

The initial Obsidian-first foundation stores vault graph data in Supabase using:

- `vaults`
- `vault_sync_runs`
- `vault_notes`
- `vault_note_links`
- `vault_note_chunks`

The FastAPI service currently supports:

- provisioning a primary managed vault for a user
- importing note batches into a vault
- parsing frontmatter and inline tags
- extracting Obsidian wikilinks
- chunking note content for future retrieval/indexing
- searching vault notes by title/path/content
- reading individual notes and backlink neighborhoods
- appending daily curator reflections back into the user's daily note

## Vault-aware daily curator

The daily curator can now:

- preload recent vault context before starting research
- seed vault context from semantically related notes when embeddings are configured
- call vault tools during tool-use loops
- consult note backlinks for related concepts
- write a curator reflection into the user's daily note after a run

Current vault-oriented tools available to the agent runtime:

- `search_vault_notes`
- `get_vault_note`
- `get_vault_backlinks`
- `append_to_daily_note`

## Semantic retrieval

The vault retrieval layer now supports optional semantic ranking over `vault_note_chunks`.

- chunk embeddings are stored on `vault_note_chunks`
- vault import can embed chunks when `OPENAI_API_KEY` is configured
- `search_vault_notes` uses semantic ranking when embeddings are available
- the service falls back to lexical vault search when embeddings are not configured

Required migration for this phase:

- `20260316_vault_chunk_embeddings.sql`

Additional environment variables:

- `OPENAI_API_KEY`
- `EMBEDDING_MODEL`
- `SEMANTIC_SEARCH_CANDIDATE_LIMIT`

### Internal vault provision request

```json
{
  "user_id": "user-uuid",
  "label": "Knowledge Graph",
  "provider": "lastfirst_managed",
  "connection_type": "managed",
  "root_path": null,
  "is_primary": true,
  "settings": {}
}
```

### Internal vault import request

```json
{
  "user_id": "user-uuid",
  "vault_id": null,
  "label": "Knowledge Graph",
  "trigger_source": "manual",
  "notes": [
    {
      "path": "Daily/2026-03-16.md",
      "content_markdown": "---\ntags: [daily, reading]\n---\n# Daily Note\nLinked to [[Philosophy]].",
      "title": "Daily Note",
      "note_type": "daily_note",
      "tags": ["reading"],
      "frontmatter": {}
    }
  ]
}
```

## Local development

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
uvicorn app.main:app --reload
```

## Railway deployment notes

- deploy the `agent_service` directory as its own service
- set the variables from `.env.example`
- expose port `8000`
- set `AGENT_SERVICE_URL` and `AGENT_SERVICE_INTERNAL_KEY` in the Supabase `curator-daily` function environment after the service is live

## Deployment timing

You should begin deploying the FastAPI/backend infrastructure **now in staging**.

Reason:

- the service contract is now broad enough to justify a real hosted runtime
- the database schema foundation is in place for vaults and semantic retrieval
- the daily curator already has an external-service bridge from Supabase

Recommended order:

1. apply the new Supabase migrations
2. deploy `agent_service` to Railway (or equivalent)
3. configure service env vars, including `OPENAI_API_KEY` if you want semantic retrieval immediately
4. set `AGENT_SERVICE_URL` and `AGENT_SERVICE_INTERNAL_KEY` in Supabase function env
5. redeploy `curator-daily`
6. test vault provision/import + delegated daily run in staging

I would treat this as **staging-ready now**, but not full production cutover yet because `curator-chat` still has not been migrated to the external service.

## Current scope

This initial cut migrates daily-curation orchestration first. `curator-chat` remains in Supabase for now and should move next once the service contract is stabilized.
