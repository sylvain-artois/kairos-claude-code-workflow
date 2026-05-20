# acme_api — Spec

> FastAPI service handling business analytics, content generation, crawl orchestration, and scheduler integration for the Acme SaaS platform.

**Last updated**: STORY-042 (2026-05-12)

## Identity & Commands

- **name**: acme_api
- **path**: acme_api
- **language**: Python 3.12
- **framework**: FastAPI
- **test_command**: `docker exec acme_api pytest api/tests/ -v`
- **lint_command**: `docker exec acme_api ruff check api/`
- **review_command**: review-api
- **suggest_test_plan**: true
- **security_review**: true

## Overview

| | |
|---|---|
| **Path** | `acme_api` |
| **Stack** | Python 3.12, FastAPI, SQLAlchemy, APScheduler |
| **Entrypoint** | `api/app/main.py` (uvicorn) |
| **Port** | 8000 |
| **Compose file** | `acme_infrastructure/compose.yml` (service `acme_api`) |

## API / Endpoints

| Method | Route | Description |
|--------|-------|-------------|
| GET | `/api/v1/analysis/{business_id}` | Fetch analysis results for a business |
| POST | `/api/v1/crawl/start` | Trigger crawl for a list of URLs |
| GET | `/api/v1/jobs/{job_id}` | Job status (running / done / failed) |
| POST | `/api/v1/generation/blog` | Generate blog content from a topic + business context |
| GET | `/api/v1/scheduler/jobs` | List currently scheduled jobs |
| POST | `/api/v1/business_content/` | Create or update business-owned content |

## Database Tables

| Table | Access | Description |
|-------|--------|-------------|
| `businesses` | READ | Business profiles and metadata |
| `analysis_runs` | READ/WRITE | Analysis runs and scores |
| `jobs` | READ/WRITE | Async job tracking (crawl, generation, scoring) |
| `generated_content` | READ/WRITE | LLM-generated blog and social drafts |
| `prompt_perf` | WRITE | Prompt latency + cost telemetry |

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `POSTGRES_DB` | yes | Postgres database name |
| `POSTGRES_USER` | yes | Postgres user |
| `POSTGRES_PASSWORD` | yes | Postgres password (vault-injected) |
| `OPENAI_API_KEY` | yes | OpenAI inference key |
| `SEARCH_API_LOGIN` | yes | External search-API basic-auth login |
| `SEARCH_API_PASSWORD` | yes | External search-API basic-auth password |
| `NLP_CREDENTIALS` | yes | Path to cloud-NLP service-account JSON |
| `MODEL_INFERENCE_URL` | yes | Remote inference endpoint for the URL-classifier model |
| `LOG_LEVEL` | no | Default `INFO` |

## Dependencies

**Upstream** (this service calls):
- PostgreSQL (managed)
- OpenAI (LLM inference)
- External search API (SERP data)
- Cloud NLP service (sentiment + entity analysis)
- Remote inference endpoint (URL classifier)

**Downstream** (calls this service):
- `acme_dashboard` (reads analysis + generation endpoints)
- `acme_infrastructure` cron jobs (call internal endpoints)

## Behavioral Contracts

**WHEN** a `/api/v1/crawl/start` request lists more than 50 URLs
**THEN** the service splits the batch into 50-URL chunks, enqueues one job per chunk, and returns the parent job id immediately.

**WHEN** a generation call to OpenAI fails with a 429 rate limit
**THEN** the service retries with exponential backoff up to 3 times; on the fourth failure the job transitions to `failed` and the error is recorded in `jobs.error_payload`.

**WHEN** a scheduled analysis job triggers for a business that has no fresh search-API snapshot in the last 24h
**THEN** the service fetches a new snapshot before running the scoring pipeline.

## Known Limitations

- No streaming responses on the generation endpoint — clients receive the full payload at once.
- Schedule changes via `/api/v1/scheduler/jobs` only take effect after the next APScheduler tick (max 60s lag).
- No tenant isolation at the database layer; `business_id` is the only access boundary and must be enforced by the caller.
- Remote-inference endpoint cold-start can take up to 15s; first crawl of the day is noticeably slower.

## Cron / Scheduled Tasks

| Schedule | Task | Description |
|----------|------|-------------|
| `0 */6 * * *` | `scheduled_crawler_service.run` | Refresh crawl for active businesses |
| `0 3 * * *` | `analysis_scheduler.daily_scoring` | Run scoring across all active businesses |
| `*/15 * * * *` | `concurrency_service.reap_stale_jobs` | Mark stuck jobs as failed after 30 min |

## LLM Prompts

| Prompt File | Model | Input | Output |
|-------------|-------|-------|--------|
| `api/app/prompts/blog_generation.yml` | gpt-4.1 | topic, business context, target length | structured blog draft (title, sections, CTA) |
| `api/app/prompts/analysis_scoring.yml` | gpt-4.1-mini | business profile, competitor snapshot | per-dimension scores + rationale |
| `api/app/prompts/url_classifier.yml` | remote:url-classifier-v3 | URL + page title | category enum |
