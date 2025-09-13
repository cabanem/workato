# Operations Runbook

## 1. Bootstrap
```
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env  # edit keys and settings
python -m src.scripts.ingest_and_index
uvicorn src.api.server:app --port 8000
```

## 2. Scheduled Refresh
- Re-run `ingest_and_index.py` daily or weekly (depends on doc churn).
- The crawler honors ETag/Last-Modified; unchanged pages are skipped.

## 3. Monitoring
- Log counts: pages fetched, extract failures, chunks, index vectors.
- Track index timestamp (touch file `data/index/.built_at`).

## 4. Troubleshooting
- **404s or site structure changes**: check `data/raw_html` and `pages.jsonl` for gaps; update `PREFIXES` if needed.
- **Extraction empty**: inspect HTML; adjust Trafilatura flags or fallback to Pandoc for that page.
- **High latency**: disable re‑ranker; reduce TOP_K; consider HNSW index type if corpus grows.
- **LLM errors**: verify API key, model name, or set `LLM_PROVIDER=none` to use Noop model.

## 5. Backup & Restore
- Back up `data/index/*` and `data/jsonl/*`. Rebuild is deterministic from `pages.jsonl` + chunking.
- Restore by copying artifacts into `DATA_DIR` and starting the API.

## 6. SLOs
- Availability ≥ 99.9% for `/ask` (single instance, best-effort).
- P95 latency (excluding LLM) ≤ 2.0 s with reranker enabled.
