# RAG Utilities — Workato custom connector

Short README to accompany the full Developer Guide.

## What it is
A Workato Connector SDK package with reusable actions for RAG workflows: chunking, email cleaning, vector similarity, prompt construction, embedding batch formatting, response validation, document diffing, simple metrics, batch‑size tuning, and rule‑based email routing.

> No triggers are defined; this connector provides actions only.

## Requirements
- Workato workspace with access to **Connector SDK**.
- **API token (Bearer)** only if you use **Data Tables** (custom templates/rules).
- Select the correct **Workato region** host to keep data residency consistent.

## Install
1. In Workato, go to **Tools → Connector SDK → New connector**.
2. Paste the provided source code and **Save**.
3. Click **Test** in the editor to compile.
4. **Release** the connector so recipes can use it.

## Connection
- **Workato region** (`developer_api_host`): one of `www`, `app.eu`, `app.jp`, `app.sg`, `app.au`, `app.il`, `app.trial`.
- **API token (Bearer)**: optional; required for Data Tables features.
- **Environment**: label only (development/staging/production).
- **RAG defaults**: `chunk_size_default`, `chunk_overlap_default`, `similarity_threshold`.

## Actions at a glance
- **Smart chunk text** — Token‑approximate chunking with sentence/paragraph boundaries and overlap.
- **Clean email text** — Strip signatures/quotes/disclaimers; normalize whitespace; optional URL extraction.
- **Calculate vector similarity** — Cosine, Euclidean (normalized to 0–1), or dot product.
- **Format embeddings for Vertex AI** — Batch `{id, vector, metadata}` to JSON/JSONL/CSV payloads.
- **Build RAG prompt** — Compile `query + context_documents` using built‑in or Data Tables templates.
- **Validate LLM response** — Heuristic checks and confidence score.
- **Generate document metadata** — Hashes, counts, naive summary/topics.
- **Check document changes** — Hash/content/smart diffs with reindex hints.
- **Calculate performance metrics** — Avg/median/stddev, p95/p99, simple trend, 2σ anomalies.
- **Optimize batch size** — Recommend batch size from history and target (throughput/latency/cost/accuracy).
- **Evaluate email against rules** — Built‑in patterns or Data Tables rule table.

## Quick start (email → answer)
1. **Clean email text** → get `cleaned_text` and `extracted_query`.
2. **Smart chunk text** on `cleaned_text`.
3. **Build RAG prompt** (built‑in or **Custom (Data Tables)** template).
4. Call your LLM.
5. **Validate LLM response**; route low‑confidence outputs to human review.

## Data Tables (customization)
- **Templates table**: defaults expect columns `name` and `content`. You may override via action config (`template_display_field`, `template_content_field`, optional `template_value_field`). Pick lists require an API token.
- **Rules table**: required columns  
  `rule_id`, `rule_type` (`sender|subject|body`), `rule_pattern` (supports `/…/` or `re:`), `action`, `priority` (integer; lower is higher), `active` (boolean).  
  Optional mapping is supported when column names differ.

## Operational notes
- Built‑in retry on 429/5xx with `Retry‑After` and jitter.
- Heuristic token estimate is **4 chars = 1 token**.
- For **dot product** without normalization, set an absolute threshold appropriate to your embedding scale.
- Record queries use `https://data-tables.workato.com/api/v1/...`; metadata uses the selected **Workato region** base.

## Troubleshooting (quick)
- **Empty pick lists** for tables/templates → add API token and confirm correct region.
- **“Table ID must be a UUID”** → copy the canonical table ID from Data Tables.
- **No matches in custom rules** → ensure required columns (or mapping) and `active=true`.
- **Context truncated** in prompts → increase `max_context_length` or trim inputs.

## Versioning
- Source `version` is **1.1**. Increment on every change. Keep a CHANGELOG next to the connector.

## Where to find details
See the **Developer Guide** for deep usage, schema, dynamic UI, rate‑limit behavior, and a full runbook.
