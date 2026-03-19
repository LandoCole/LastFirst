# Agent Service Repo Split

This directory is ready to live in its own GitHub repository.

## What belongs in the standalone repo

Keep these files in the new repo:

- `app/`
- `pyproject.toml`
- `Dockerfile`
- `.env.example`
- `.gitignore`
- `.dockerignore`
- `README.md`

## What should stay in the current app repo

Keep these in the current LastFirst repo:

- `supabase/functions/`
- `supabase/migrations/`
- iOS app code under `LastFirst/`
- Xcode project files

The standalone service depends on the Supabase schema at runtime, but it does not need the migration files inside the deployable service repo.

## Recommended extraction path

Use `git subtree split` if you want clean history for the new repo.

### 1. Create a split branch from the monorepo

```bash
git subtree split --prefix=agent_service -b agent-service-split
```

### 2. Create a new local repo from that split

```bash
git clone . ../lastfirst-agent-service
git -C ../lastfirst-agent-service checkout agent-service-split
git -C ../lastfirst-agent-service checkout --orphan main
git -C ../lastfirst-agent-service add .
git -C ../lastfirst-agent-service commit -m "Initial standalone agent_service import"
git -C ../lastfirst-agent-service branch -D agent-service-split
```

If you prefer a simpler copy without history, use:

```bash
mkdir -p ../lastfirst-agent-service
rsync -av --delete agent_service/ ../lastfirst-agent-service/
cd ../lastfirst-agent-service
git init -b main
git add .
git commit -m "Initial standalone agent_service import"
```

## 3. Create the GitHub repo and push

Example:

```bash
git -C ../lastfirst-agent-service remote add origin git@github.com:<your-org>/lastfirst-agent-service.git
git -C ../lastfirst-agent-service push -u origin main
```

## 4. Connect Railway

In Railway:

- create a new project from the new GitHub repo
- let Railway build from the repo root
- use the existing `Dockerfile`
- expose port `8000`

## 5. Set Railway environment variables

Required:

- `AGENT_SERVICE_INTERNAL_KEY`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ANTHROPIC_API_KEY`

Optional:

- `FIRECRAWL_API_KEY`
- `OPENAI_API_KEY`
- `EMBEDDING_MODEL`
- `SEMANTIC_SEARCH_CANDIDATE_LIMIT`
- `APP_ENV`
- `AGENT_DEFAULT_MODEL`
- `AGENT_DEFAULT_MAX_ITEMS`
- `AGENT_DEFAULT_HISTORY_LIMIT`

## 6. Point Supabase at the deployed service

After Railway gives you a stable URL, set these secrets for the Supabase function runtime:

- `AGENT_SERVICE_URL`
- `AGENT_SERVICE_INTERNAL_KEY`

Then redeploy `curator-daily`.

## 7. Validate staging

Run these checks after deployment:

- `GET /health`
- `POST /internal/vaults/provision`
- `POST /internal/vaults/import`
- `POST /internal/daily-curations/run`
- confirm daily-note writeback and semantic vault search behavior

## Current recommendation

Use a dedicated GitHub repo for `agent_service` and connect that repo directly to Railway.
This is the cleanest deployment boundary for the backend runtime.
