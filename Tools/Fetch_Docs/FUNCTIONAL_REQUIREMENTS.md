# Functional & Non‑Functional Requirements

## 1. Functional Requirements (FR)
**FR1 – Crawl Scope & Recency**
- Crawl **only** pages under `/developing-connectors/sdk` (and `/en/…`) on `docs.workato.com`.
- Honor `robots.txt`, `If-None-Match` (ETag) and `If-Modified-Since` for incremental updates.
- Skip binary assets (images, pdfs, videos).

**FR2 – Extraction & Normalization**
- Extract main content as Markdown preserving headings, lists, links, and fenced code blocks.
- Persist raw HTML and extracted Markdown to disk for auditability.

**FR3 – Chunking**
- Token‑aware chunking target **~1200 tokens** with **150** overlap.
- Avoid splitting inside fenced code blocks.
- Associate each chunk with source URL and stable chunk id.

**FR4 – Indexing & Retrieval**
- Generate dense embeddings and store in FAISS (cosine via normalized vectors).
- Retrieve top‑K (default 40), optionally re‑rank to final K (default 8).

**FR5 – Answer Generation & Citations**
- Build prompts from top contexts; instruct model to only answer from context.
- Return citations with URL and retrieval score in response payload.

**FR6 – API & CLI**
- Expose POST `/ask` with request: `{ query, k? }` and response: `{ answer, citations[], contexts[] }`.
- Provide `python -m src.scripts.ask "question"` CLI.

**FR7 – Configuration**
- All tunables (models, K values, paths, provider API keys) via `.env` and `config.py` defaults.

**FR8 – Observability**
- Log ingestion counts, index sizes, retrieval scores; expose errors with actionable messages.

## 2. Non‑Functional Requirements (NFR)
- **Performance**: P95 query latency ≤ 2.0 s on laptop CPU with re‑ranker enabled (excluding LLM).
- **Reliability**: Index build should tolerate transient HTTP failures and continue.
- **Security**: No transmission of user queries or documents to third parties beyond chosen LLM provider.
- **Compliance**: Respect site terms and robots; clearly attribute sources.
- **Portability**: No vendor lock‑in—swap embedding/LLM models without refactor.
- **Maintainability**: Code modular (ingest/index/query/api), type‑hints where practical, clear logging.
