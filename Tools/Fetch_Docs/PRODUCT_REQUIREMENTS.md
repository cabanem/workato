# Product Requirements Document (PRD)

## 1. Summary
Deliver a developer‑facing “Ask the Workato Connector SDK” capability that answers questions using the official docs section under `/developing-connectors/sdk/`. The system retrieves relevant excerpts, generates concise answers, and cites sources.

## 2. Goals & Non‑Goals
**Goals**
- Enable engineers to ask natural‑language questions about the Connector SDK and get accurate, cited answers.
- Keep answers up‑to‑date via re‑crawling with minimal operational overhead.
- Provide a simple HTTP endpoint and CLI for integration into portals, bots, or IDE assistants.

**Non‑Goals**
- Editing or pushing changes to the Workato docs.
- Handling user‑uploaded documents (v1).
- Building a full UI; we provide an API for downstream UIs.

## 3. Personas & Use Cases
**Personas**
- *Integration Engineer*: implementing connectors, needs examples and API specifics.
- *Solution Architect*: evaluating feasibility, best practices, and patterns.
- *Support Engineer*: answering customer questions quickly with citations.

**Core Use Cases**
1. “How do I define actions and triggers in the Connector SDK?”
2. “What’s the CLI command to scaffold a new connector?”
3. “How to package, version, and publish a connector?”
4. “Where are rate limits or authentication examples?”

## 4. Success Metrics (North Star & KPIs)
- **Answer usefulness** ≥ 80% (thumbs‑up rate) on internal dogfooding.
- **Citation click‑through** ≥ 30% (indicates trust + exploration).
- **Retrieval hit rate@k** ≥ 90% on curated QA set (answerable questions).
- Index rebuild completes within **≤ 5 minutes** for the SDK section.

## 5. Requirements Summary
- Provide POST `/ask` returning `{ answer, citations[] }` with stable schema.
- Provide CLI `ask.py "question"` for local usage.
- Provide incremental ingestion (ETag/Last‑Modified) and robots.txt politeness.
- Optional re‑ranking for quality; configurable.
- Configurable embedding and LLM providers.

## 6. Out of Scope / Future
- Hybrid lexical+dense search, structured field extraction, UI web app, multi‑site ingestion, advanced evaluations.
