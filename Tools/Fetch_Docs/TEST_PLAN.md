# Test Plan

## 1. Unit Tests
- **crawl.py**
  - Mocks for HTTP with ETag / Last‑Modified handling.
  - Robots disallow/allow logic.
  - Link discovery in-scope filter.
- **chunk.py**
  - Code-fence detection (never split inside).
  - Header-aware sectioning.
  - Token budget adherence and overlap.
- **embedder.py**
  - Embedding dimension and normalization.
- **faiss_store.py**
  - Add/save/load/search round-trip; id/metadata alignment.
- **retriever.py**
  - TOP_K retrieval; FINAL_K truncation; RERANK on/off behavior.
- **provider.py**
  - Prompt assembly; Noop vs OpenAI provider path.

## 2. Integration Tests
- Ingest a small fixture site (local HTML) → ensure pages/chunks/index artifacts produced.
- Query known Q/A pairs → ensure top contexts include gold passage (hit@k≥0.9).

## 3. End‑to‑End (E2E)
- Start API → POST /ask → ensure 200, citations nonempty, answer not empty (when LLM enabled).

## 4. Quality Evaluation
- Curate ~50 QA items from docs; report:
  - Retrieval hit@k (k=5,10)
  - Answer exact/partial match (human eval or regex heuristics)
  - Latency distribution (p50/p95).

## 5. Tooling
- Use `pytest`, `requests-mock`, and synthetic fixtures.
- Optional: GitHub Actions to run tests and linting on PRs.
