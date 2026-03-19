# Railway Monorepo Deployment

This is the recommended deployment path **right now** while `agent_service` still lives inside the main LastFirst repo.

## What Railway should build

Use the `agent_service` directory as the Railway service root.

That means Railway should build from this folder:

```text
agent_service/
```

The deployable service contents are:

- `app/`
- `pyproject.toml`
- `Dockerfile`
- `.dockerignore`

Railway does **not** need the iOS app, Xcode project, or Supabase migrations inside the running service container.

## Railway setup

### 1. Create a new Railway service from the current GitHub repo

In Railway:

- create a new project or service from GitHub
- select the current LastFirst repository
- set the **Root Directory** to `agent_service`
- let Railway detect and build the `Dockerfile`

### 2. Configure environment variables

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

## Runtime behavior

The container now listens on Railway's assigned `PORT` automatically, with local fallback to `8000`.

## After first deploy

Once Railway gives you a stable public URL:

1. set `AGENT_SERVICE_URL` in the Supabase function environment
2. set the same `AGENT_SERVICE_INTERNAL_KEY` in the Supabase function environment
3. redeploy the `curator-daily` function

## Smoke tests

After deploy, validate:

- `GET /health`
- `POST /internal/vaults/provision`
- `POST /internal/vaults/import`
- `POST /internal/daily-curations/run`

## Later cleanup

Once staging is stable, you can split `agent_service` into its own repo and keep the same Docker/Railway setup with almost no changes.
