# Data Model & Storage

## Files & Artifacts
- `data/raw_html/*.html` — raw page snapshots
- `data/md/*.md` — extracted Markdown (header includes source URL)
- `data/jsonl/workato_sdk_pages.jsonl` — page-level records
  - `{ id, url, title, markdown }`
- `data/jsonl/workato_sdk_chunks.jsonl` — chunk-level records
  - `{ id, url, text }`
- `data/index/workato_sdk.faiss` — FAISS index
- `data/index/workato_sdk_meta.jsonl` — aligned metadata for vectors
  - `{ id, url, text_head }`
- `data/index/workato_sdk_ids.json` — id list aligned with FAISS rows

## Identifiers
- **Page id**: slug from URL path + short md5 suffix
- **Chunk id**: `"{page_id}#{ordinal}"`

## Retrieval Scores
- FAISS returns inner-product similarity on normalized vectors ∈ [−1, 1].
- Re‑ranker score is an uncalibrated relevance score; higher is better.
