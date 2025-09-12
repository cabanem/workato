# Workato Connector SDK — RAG System Documentation
_Last updated: 2025-08-28_

This bundle contains a complete set of documents for the “ask‑the‑docs” RAG system over the **Workato Connector SDK** documentation.

**Contents**

- [PRODUCT_REQUIREMENTS.md](PRODUCT_REQUIREMENTS.md) — Product Requirements Document (PRD)
- [FUNCTIONAL_REQUIREMENTS.md](FUNCTIONAL_REQUIREMENTS.md) — Functional & Non‑Functional requirements (behavioral spec)
- [ENGINEERING_SPEC.md](ENGINEERING_SPEC.md) — Engineering specification (modules, interfaces, configs)
- [TECHNICAL_DESIGN.md](TECHNICAL_DESIGN.md) — Architecture, data flow, algorithms, diagrams
- [API_SPEC.md](API_SPEC.md) — HTTP API contract for querying answers
- [DATA_MODEL.md](DATA_MODEL.md) — Metadata & storage formats
- [TEST_PLAN.md](TEST_PLAN.md) — Unit/integration/e2e test strategy and cases
- [OPERATIONS_RUNBOOK.md](OPERATIONS_RUNBOOK.md) — Deploy, operate, troubleshoot, SLOs
- [SECURITY_PRIVACY.md](SECURITY_PRIVACY.md) — Threat model, data handling, compliance
- [ROADMAP.md](ROADMAP.md) — Near‑term and future enhancements

The doc set aligns with the Python implementation previously provided (crawler → chunker → index → retriever → optional re‑ranker → LLM → API).
