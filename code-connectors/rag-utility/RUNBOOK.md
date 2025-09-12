# RAG Utilities (Workato custom connector): Developer guide and runbook

This guide explains how to use, extend, and troubleshoot the **RAG Utilities** custom connector in enterprise environments. It follows Google’s developer documentation style (sentence case headings, short paragraphs, numbered steps for procedures).([Google for Developers][1])

---

## What this connector does

The connector provides reusable actions to support retrieval‑augmented generation (RAG) workflows—text chunking, email cleaning, vector similarity, prompt construction, batch formatting for vector stores, lightweight validation, change detection, and simple analytics.

It’s built on the Workato Connector SDK (Ruby DSL) and uses standard SDK patterns: `connection`, `test`, `actions`, `object_definitions`, `methods`, and `pick_lists`. If you’re new to the SDK, skim the SDK overview and reference first.([Workato Docs][2])

---

## Who should use this

* **Recipe builders** who want drop‑in RAG utilities.
* **SDK developers** who may extend the connector (add actions, harden error handling, or integrate vendor APIs).
* **Ops/Platform teams** who need a runbook for incidents (429s, region mismatches, Data Tables schema errors).

---

## Before you begin

1. **Access**: A Workato workspace with permission to create custom connectors and read Data Tables (if you plan to use custom templates/rules).([Workato Docs][3])
2. **Developer API token (optional)**: Required only when the connector must read Data Tables (custom templates and custom rules). The base URL depends on your Workato data center (US/EU/JP/SG/AU/IL/Trial).([Workato Docs][4])
3. **Data center awareness**: Confirm where your account is hosted and choose the matching host (for compliance and latency).([Workato Docs][5])
4. **Familiarity with SDK schema, config fields, and `ngIf`**: This connector uses dynamic fields and conditional UI. The `ngIf` expression root is `input`.([Workato Docs][6])
5. **Ruby in the SDK**: Only a subset of Ruby methods is available in the Workato SDK runtime. If you plan to modify methods, confirm availability.([Workato Docs][7])

---

## Install and release

1. Go to **Tools → Connector SDK**, create a new connector, paste the provided source, and **Save**.
2. Use the **Test** button in the SDK editor to compile and validate.
3. **Release** the connector so recipe builders can find it in the app picker.([Workato Docs][8])

---

## Connection configuration

The connection intentionally separates **region selection**, **auth**, and **RAG defaults**:

* **Workato region** (`developer_api_host`): Static dropdown mapping to data‑center base URLs for the Developer API. Example: `www` (US), `app.eu` (EU). This is the prefix used by `base_uri` for `/api/*` endpoints (for identity checks and Data Tables metadata).([Workato Docs][4])
* **API token (Bearer)**: Optional—but required when you read **Data Tables** (for custom templates and rules). The connector sends `Authorization: Bearer …` on Developer API calls.([Workato Docs][9])
* **Environment**: Purely a label (development/staging/production) to tag executions.
* **RAG defaults**: Default chunk size/overlap and a **similarity threshold** (used unless overridden per action).

> **Note:** In connection fields, static dropdowns use `options` (not `pick_list`). That’s by design—`pick_list` isn’t available at connection time.([Workato Docs][10])

### How the connection test works

The `test` lambda:

* Returns context (environment, region) even without a token.
* If a token is present, it calls `GET /api/users/me` to validate identity and `GET /api/data_tables` (page 1) to check reachability. Errors here surface as a readable status. The behavior aligns with typical SDK testing patterns.([GitHub][11])

---

## Data Tables domains and endpoints used

The connector calls **two API surfaces**:

* **Developer API** (for table metadata): `https://<region>.workato.com/api/*` (e.g., `/api/data_tables`, `/api/data_tables/:id`). Region is taken from **Workato region**.([Workato Docs][4])
* **Record manipulation APIs** (for rows): `https://data-tables.workato.com/api/v1/tables/:id/...` including `POST /query`, `POST /records`, etc. This is the correct base for record reads/writes and supports **continuation\_token** pagination.([Workato API Documentation][12])

---

## Security and compliance

* **Least privileges**: The API token is needed only when you read Data Tables (custom templates/rules). Store the token in a secure connection field.
* **Region pinning**: Selecting the correct data center keeps data residency aligned with policy.([Workato Docs][5])
* **Regex safety**: User‑supplied patterns are sanitized and length‑limited (512 chars) before compilation.
* **PII**: `clean_email_text` and `generate_document_metadata` process raw content—review recipe logging settings and downstream storage as part of your data handling policy.

---

## Actions: when to use what

Below is a concise, field‑oriented view. For schema mechanics (types, `convert_input`, `support_pills`, and `list_mode_toggle`), see the SDK Schema reference.([Workato Docs][6])

### 1) Smart chunk text

**Use it to** split long text into token‑approximate segments using smart boundaries and overlap.

* **Inputs**

  * **Configuration mode**: *Use connection defaults* or *Custom*. If *Custom*, extra fields from `chunking_config` appear (via dynamic schema).([Workato Docs][13])
  * **Input text** (required)
  * Optional: `chunk_size`, `chunk_overlap`, `preserve_sentences`, `preserve_paragraphs`
* **Behavior**

  * Assumes \~4 chars/token when estimating size.
  * Respects paragraph (`\n\n`) and sentence (`[.!?]["')]]?\s`) boundaries where possible.
  * Enforces `chunk_size > 0`, `chunk_overlap ≥ 0`.
* **Output**

  * `chunks[]` with `chunk_id`, `start_char/end_char`, `token_count`; `total_chunks`, `total_tokens`.

### 2) Clean email text

**Use it to** normalize emails for RAG (strip signatures, quoted sections, common disclaimers; normalize whitespace; optionally extract URLs).

* **Inputs**: `email_body` plus toggles `remove_signatures`, `remove_quotes`, `remove_disclaimers`, `normalize_whitespace`, `extract_urls`.
* **Output**: `cleaned_text`, `extracted_query` (first non‑empty paragraph), `removed_sections[]`, `extracted_urls[]`, and reduction stats.

### 3) Calculate vector similarity

**Use it to** compute similarity (cosine, euclidean, or dot product) between two numeric arrays.

* **Inputs**

  * **Config field**: *Similarity method* (cosine/euclidean/dot product). Renders `normalize` option except for dot product. Dynamic fields are implemented via `config_fields`.([Workato Docs][13])
  * **Vectors**: `vector_a[]`, `vector_b[]`
* **Validation**

  * Same length, non‑empty, numeric‑only.
  * For **dot product without normalization**, the method aborts and instructs you to set an **absolute threshold** appropriate to your embedding scale.
* **Thresholding**

  * Uses the connection‑level `similarity_threshold` for cosine/euclidean (0–1 similarity), and for dot product *if* vectors are normalized.

### 4) Format embeddings for Vertex AI

**Use it to** convert an array of `{id, vector[], metadata}` into batches and a serialized payload (JSON/JSONL/CSV) ready for ingestion into a vector service. The format uses keys `{datapoint_id, feature_vector, restricts}` commonly expected by vector indices.

* **Inputs**: `embeddings[]`, `index_endpoint` (string), `batch_size` (default 25), `format_type` (*json*, *jsonl*, *csv*).
* **Output**: `formatted_batches[]`, `payload` (full serialized body), counts, and the selected format.

> Verify the target service’s ingestion schema before posting. The connector only formats the payload.

### 5) Build RAG prompt

**Use it to** assemble a prompt from a user **query** and **context\_documents\[]**, optionally using built‑in or **Data Tables** templates.

* **Config**

  * **Prompt configuration**: *Template‑based* or *Custom instructions*.
  * **Template source**: *Built‑in* or *Custom (Data Tables)*. If *Custom*, `templates_table_id` dropdown resolves via the **tables** pick list and your API token.([Workato Docs][14])
  * Conditional UI uses `ngIf` with the `input` root (for example, to show the table field only when *Custom* is selected).([Workato Docs][6])
* **Inputs**

  * `query` (string), `context_documents[]` ({content, relevance\_score, source, metadata})
  * If template‑based: **Prompt template**—either a built‑in key (*standard*, *customer\_service*, *technical*, *sales*) or a **Custom** selection from Data Tables (supports inline text fallback).
  * Optional **Advanced settings**: `max_context_length` (tokens, 4 chars/token heuristic) and `include_metadata` (append JSON metadata per doc).
* **Behavior**

  * Sorts context by `relevance_score` descending, packs until `max_context_length` is reached, and compiles the template (supports `{{context}}` and `{{query}}` placeholders).
* **Output**: `formatted_prompt`, `token_count`, `context_used`, `truncated` flag, and `prompt_metadata` (includes source and template info).

### 6) Validate LLM response

**Use it to** run light heuristics on an LLM’s output.

* **Checks**: empty/too short, core token overlap with the original query, presence/absence rules, and “incomplete” markers.
* **Output**: `is_valid`, `confidence_score` (0–1), `issues_found[]`, `requires_human_review` (true if confidence < 0.5), `suggested_improvements[]`.

### 7) Generate document metadata

**Use it to** compute a content hash, estimates, and a naive summary/entities set for indexing.

* **Outputs**: `document_id` (SHA1 of path + content hash), `file_hash` (SHA256), `word_count`, `estimated_tokens`, `summary` (first 200 chars), `key_topics[]` (simple frequency), `created_at`, `processing_time_ms`.

### 8) Check document changes

**Use it to** determine whether a document changed and how.

* **Modes**

  * **Hash only**: fast inequality check.
  * **Content diff**: line‑based, returns added/removed/modified blocks and a line change percentage.
  * **Smart diff**: line diff + token overlap to produce a coarse “% changed” score.
* **Output**: `has_changed`, `change_type` (`hash_changed`, `content_changed`, `smart_changed`, `none`), diffs, and `requires_reindexing`.

### 9) Calculate performance metrics

**Use it to** compute aggregates and basic anomaly detection for a time‑series list of `{timestamp, value}`.

* **Outputs**: average, median, min/max, stddev, p95/p99, naive trend (compare first/second half), and points > 2σ as anomalies.

### 10) Optimize batch size

**Use it to** recommend a batch size based on historical runs and an optimization target.

* **Targets**: throughput, latency, cost, accuracy.
* **Fallback**: If no history, it uses a simple heuristic with moderate confidence.

### 11) Evaluate email against rules

**Use it to** route emails by **standard patterns** or **custom rules from a Data Table**.

* **Config**

  * **Rules source**: *Standard* or *Custom (Data Tables)*.
  * If *Custom*: choose **Rules table**, optionally enable **Custom column names** and map required columns. The table and columns are fetched dynamically (pick lists), using your token and the SDK’s dynamic field capabilities.([Workato Docs][15])
* **Inputs**

  * `email` object (from, subject, body, headers, message\_id).
  * `stop_on_first_match` (default true), `fallback_to_standard` (default true), `max_rules_to_apply`.
* **Behavior**

  * If **Custom**: validates `table_id` format, verifies schema has `{rule_id, rule_type, rule_pattern, action, priority, active}` (or mapped variants), queries active rows via **record APIs** with pagination, then applies regex rules safely.
  * **Standard**: flags common automated senders and transaction emails (no‑reply, receipts, confirmation, invoice) by sender/subject/body regex.
* **Output**

  * `pattern_match`, `rule_source` (`custom`, `standard`, `none`), `selected_action` (top match’s action), `top_match`, `matches[]`, and `standard_signals`.
  * `debug`: `evaluated_rules_count`, `schema_validated`, `errors[]`.

---

## Dynamic UI patterns used (SDK specifics)

* **Config fields** drive which inputs render. They are shown before input fields and are meant to alter the latter. This connector uses them in the *Similarity* and *Build RAG prompt* actions.([Workato Docs][13])
* **`ngIf`** is used to hide/show fields based on other inputs. The expression’s root is `input`. Example: `ngIf: 'input.template_source == "custom"'`.([Workato Docs][6])
* **`convert_input`** coerces types early (integers, floats, booleans, timestamps), so `execute` receives correctly typed values.([Workato Docs][6])
* **`support_pills`** is set to `false` on certain connection/config fields to avoid misleading datapill mapping.([Workato Docs][6])
* **Array inputs** use `list_mode_toggle` where appropriate to allow static vs. dynamic lists.([Workato Docs][16])

---

## Error handling, retries, and rate limits

* **HTTP retry strategy**: The helper `execute_with_retry` retries on **429** and **5xx** up to 3 times with exponential backoff and **`Retry-After`** support. Jitter is added to reduce thundering herd.
* **Data Tables** throttling\*\*:\*\* published limits are typically **60 requests/min** for Data Table resources on the Developer API. Consider leaving room for recipe concurrency or add upstream batching.([Workato Docs][17])
* **Record APIs base**: When querying rows, calls go to `data-tables.workato.com` via `/api/v1/tables/:id/query`, which supports `continuation_token`. Plan for pagination.([Workato API Documentation][12])
* **SDK HTTP helpers**: Actions use SDK `get/post` helpers; see the SDK HTTP methods reference if you extend them.([Workato Docs][18])

---

## Troubleshooting runbook

Use these quick checks during incidents.

### Connection/test issues

* **Symptom**: Test returns *connected (no API token)* but templates/rules pick lists are empty.
  **Cause**: No token in connection; Data Tables need a token.
  **Fix**: Add an API token and select the correct **Workato region**. Confirm the base URL matches your data center.([Workato Docs][4])

* **Symptom**: *Failed to load tables (403/404/422/5xx)… cid=…*
  **Cause**: Token lacks permission, wrong region, or table service unavailable.
  **Fix**: Verify token scope, region host, and table ID. Capture the **x‑correlation‑id** from the error and contact support with it.

### Data Tables (custom rules/templates)

* **Symptom**: *Table ID must be a UUID*
  **Fix**: Paste the canonical table ID from Data Tables UI/Developer API (`/api/data_tables`).([Workato Docs][9])
* **Symptom**: *Rules table missing required fields: …*
  **Fix**: Ensure the table has columns `{rule_id, rule_type, rule_pattern, action, priority, active}` or map them using **Custom column names**.
* **Symptom**: *No templates found in selected table* in the **Prompt template** picker.
  **Fix**: Ensure the table has at least `name` and `content` columns (defaults), or set `template_display_field` / `template_content_field` to your custom column names.([Workato Docs][14])

### Similarity calculations

* **Symptom**: *Vectors must be the same length* or *Vectors must contain only numerics.*
  **Fix**: Normalize both arrays upstream; map only numeric lists. Consider using formula mode to coerce values if needed.([Workato Docs][19])
* **Symptom**: *For dot\_product without normalization… absolute threshold*
  **Fix**: Either enable **Normalize vectors** or set a scale‑appropriate threshold per your embedding model.

### Prompt building

* **Symptom**: Context seems truncated.
  **Cause**: `max_context_length` budget reached (4 chars/token heuristic).
  **Fix**: Increase `max_context_length` or pass fewer/lighter documents.

### Diffing and change detection

* **Symptom**: *Smart diff* reports low change % despite edits.
  **Fix**: Use **Content diff** to get explicit line blocks; *smart* is designed for coarse gating.

### API rate limits / 429s

* **Symptom**: Intermittent 429s on rule/template queries.
  **Fix**: Retry logic is built‑in, but reduce batch sizes and parallelism. Published Data Tables limits are 60 req/min per resource.([Workato Docs][17])

---

## Common recipe patterns

### RAG reply to inbound email (no external vector DB)

1. **Clean email text** → get `cleaned_text` and `extracted_query`.
2. **Smart chunk text** on `cleaned_text` to produce chunks.
3. **Evaluate email against rules** (custom rules from a table or built‑ins) → pick an automation path.
4. **Build RAG prompt** using `extracted_query` and selected chunks (with optional custom template).
5. Call your LLM; then **Validate LLM response**; route to human review if `requires_human_review`.

> For dynamic forms and good UX, rely on `config_fields`, `ngIf`, `pick_lists`, and `convert_input` per SDK guidance.([Workato Docs][13])

### Ingestion to a vector index

1. Compute embeddings in your model of choice.
2. **Format embeddings for Vertex AI** with the target `index_endpoint` and `format_type`.
3. Use HTTP connector/API Platform to POST the payload to the index endpoint.

---

## Extending the connector (SDK notes)

* **Add actions/triggers** by following the SDK reference for action anatomy and input/output schema. Keep input field sets small and self‑describing; attach `help` objects.([Workato Docs][20])
* **HTTP**: When calling external endpoints, prefer relative paths with `base_uri`. In this connector, `base_uri` points to your selected Workato region; use absolute URLs for `data-tables.workato.com` record APIs.([Workato Docs][21])
* **Ruby availability**: Confirm method availability in the **Available Ruby methods** doc when introducing new helpers.([Workato Docs][7])
* **Testing and CLI**: If you develop locally, the SDK Gem and CLI support `workato exec test` and RSpec/VCR.([Workato Docs][22])

---

## Known limitations and design choices

* **Token estimate** is a 4‑chars‑per‑token heuristic. Real tokenizers differ by model.
* **Similarity (euclidean)** returns `1/(1+dist)` to normalize into 0–1.
* **Standard email rules** are intentionally conservative (transactional mail patterns, no‑reply senders).
* **Version field** in the source is metadata for humans. Manage deployable versions from the SDK “Versions” tab.([Workato Docs][23])

---

## Reference appendix

### Required columns for **custom rules** tables

* `rule_id` (string)
* `rule_type` (sender|subject|body)
* `rule_pattern` (string/regex; supports `re:` or `/…/`)
* `action` (string)
* `priority` (integer; lower is higher priority)
* `active` (boolean)

### Required columns for **custom templates** tables

* `name` (display) and `content` (template body) by default; or provide `template_display_field`, `template_content_field`, and optional `template_value_field`. The **tables** and **table\_columns** pick lists are resolved via the Developer API and table schema.([Workato Docs][14])

### Pick lists defined

* `similarity_types`, `format_types`, `prompt_templates` (built‑in or table‑backed), `file_types`, `check_types`, `metric_types`, `time_periods`, `optimization_targets`, `devapi_regions`, `tables`, `table_columns`. See the SDK pick list reference for behaviors and constraints.([Workato Docs][15])

---

## Style, formatting, and contributor guidance

If you extend this documentation or add in‑product help strings, follow the Google developer documentation style (short sentences, sentence case headings, and precise UI vocabulary). Use numbered lists for step‑by‑step procedures and bold for UI labels.([Google for Developers][1])

---

## Quick diagnostics matrix

| Symptom                             | Likely cause                                                   | Where it happens          | What to do                                                                                          |
| ----------------------------------- | -------------------------------------------------------------- | ------------------------- | --------------------------------------------------------------------------------------------------- |
| *Failed to load tables (xxx) cid=…* | Wrong region, token missing/insufficient, or transient 5xx     | Tables pickers / test     | Check region host, confirm token, retry. Capture **correlation id** for support.([Workato Docs][4]) |
| Custom **Rules** shows no matches   | Table missing required columns or `active=false`               | `evaluate_email_by_rules` | Fix schema; verify mapping if **Custom column names** enabled.                                      |
| 429 on Data Tables query            | Hitting published limits                                       | Rules/templates query     | Reduce calls; rely on built‑in retry; consider batching.([Workato Docs][17])                        |
| Vector similarity fails             | Length mismatch or non‑numeric entries                         | `calculate_similarity`    | Normalize lists; ensure arrays are equal length and numeric‑only.                                   |
| Prompt is generic and context‑poor  | `max_context_length` budget too tight or low `relevance_score` | `build_rag_prompt`        | Raise limit; pre‑filter or re‑rank context.                                                         |
| “Connected (no API token)”          | Token not set                                                  | Connection test           | Add token if using custom templates/rules; otherwise optional.                                      |

---

## References

* **Workato Connector SDK**: Overview, actions, schema, connection, HTTP methods, pick lists, and best practices.([Workato Docs][2])
* **Dynamic inputs** (`config_fields`, `ngIf`, `list_mode_toggle`) and object definitions.([Workato Docs][13])
* **Developer API** base URLs by data center.([Workato Docs][4])
* **Data Tables**: concepts, Developer API resources, and **record manipulation base** (`data-tables.workato.com`).([Workato Docs][3])
* **Google developer documentation style**: highlights and style fundamentals for contributions.([Google for Developers][1])

---

### Where to go next

* Add guardrails or telemetry to `execute_with_retry` (capture `Retry-After` and job IDs in action outputs for observability).
* Consider a “vector dimension check” in **Calculate vector similarity** and **Format embeddings** to catch model mismatches early.
* If you need local development, use the SDK Gem and CLI (RSpec + VCR).([Workato Docs][22])

[1]: https://developers.google.com/style/highlights "Highlights | Google developer documentation style guide"
[2]: https://docs.workato.com/developing-connectors/sdk.html "Connector SDK"
[3]: https://docs.workato.com/data-tables.html "Data tables"
[4]: https://docs.workato.com/workato-api.html "Workato API - Introduction"
[5]: https://docs.workato.com/datacenter/datacenter-overview.html "Data center overview"
[6]: https://docs.workato.com/developing-connectors/sdk/sdk-reference/schema.html "SDK Reference - Schema | Workato Docs"
[7]: https://docs.workato.com/developing-connectors/sdk/sdk-reference/ruby_methods.html "Ruby Methods - SDK"
[8]: https://docs.workato.com/developing-connectors/sdk/quickstart/quickstart.html "Using the Workato Connector SDK"
[9]: https://docs.workato.com/workato-api/resources.html "Workato API - Resources"
[10]: https://docs.workato.com/developing-connectors/sdk/sdk-reference/connection.html "SDK Reference - Connection"
[11]: https://github.com/workato/workato-connector-sdk "workato/workato-connector-sdk"
[12]: https://api-docs.workato.com/workato-api/resources/data-tables "Data tables | Workato | Documentation"
[13]: https://docs.workato.com/developing-connectors/sdk/guides/config_fields.html "How-to guides - Using Config fields"
[14]: https://docs.workato.com/developing-connectors/sdk/sdk-reference/object_definitions.html "SDK Reference - Object_definitions"
[15]: https://docs.workato.com/developing-connectors/sdk/sdk-reference/picklists.html "SDK Reference - Pick Lists"
[16]: https://docs.workato.com/developing-connectors/sdk/sdk-reference/schema.html "SDK Reference - Schema"
[17]: https://docs.workato.com/workato-api/data-tables.html "Data tables - Workato API"
[18]: https://docs.workato.com/developing-connectors/sdk/sdk-reference/http.html "HTTP Methods - SDK"
[19]: https://docs.workato.com/formulas/array-list-formulas.html "List and Hash Formulas"
[20]: https://docs.workato.com/developing-connectors/sdk/sdk-reference/actions.html "SDK Reference - Actions"
[21]: https://docs.workato.com/developing-connectors/sdk/guides/authentication/oauth/auth-code.html "How-to Guide - OAuth 2.0 Authorization Code Variant"
[22]: https://docs.workato.com/developing-connectors/sdk/cli/guides/getting-started.html "Getting Started with the SDK Gem"
[23]: https://docs.workato.com/developing-connectors/sdk/quickstart/version-control.html "Version control"
