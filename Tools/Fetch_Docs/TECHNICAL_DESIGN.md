# Technical Design Document

## 1. Architecture Overview
```mermaid
flowchart LR
  A[Crawler] --> B[Page JSONL]
  B --> C[Chunker]
  C --> D[Embeddings]
  D --> E[FAISS Index]
  F[Query] --> G[Retriever + (Re-ranker)]
  G --> H[Prompt Builder]
  H --> I[LLM]
  I --> J[Answer + Citations]
  E --> G
```

### Components
- **Crawler (ingest/crawl.py)**: robots-aware, conditional GET, extract Markdown via Trafilatura.
- **Chunker (ingest/chunk.py)**: token-aware, code-fence safe, header-preferred boundaries.
- **Embedder (index/embedder.py)**: BGE small (instruction-tuned); query and passage prompts.
- **Store (index/faiss_store.py)**: FAISS IndexFlatIP (cosine via normalized vectors) + JSONL metadata.
- **Retriever (query/retriever.py)**: dense retrieval TOP_K; optional cross-encoder re-ranking to FINAL_K.
- **LLM (llm/provider.py)**: pluggable; builds context-rich prompt and calls provider.
- **API (api/server.py)**: FastAPI `POST /ask` returns answer + citations.

## 2. Data Flow
1. **Ingest** → crawl pages under scope → extract Markdown → write page JSONL.
2. **Chunk** → split Markdown into ~1200-token overlapping chunks, preserve code fences.
3. **Index** → embed chunks → store vectors + metadata in FAISS/JSONL.
4. **Query** → embed query → FAISS search (TOP_K=40) → optional re-rank → select FINAL_K=8 contexts.
5. **Answer** → construct prompt with numbered context blocks → call LLM → return answer + `[n]` citations mapping to block URLs.

## 3. Algorithms & Rationale
- **Dense embeddings (BGE small)**: strong performance and small footprint; instruction prompts improve retrieval alignment.
- **Cosine similarity via IndexFlatIP**: L2-normalized vectors; simple and fast for ≤ few million vectors.
- **Re-ranking (MiniLM cross-encoder)**: improves precision at top-k with modest latency.
- **Chunking**: token budget aligned to mid-size context LLMs; overlap reduces boundary loss; avoid splitting fenced code for developer docs.

## 4. Scaling & Performance
- **Index size**: O(N·d); with bge-small (384d) and ~3k chunks, memory << 100MB.
- **Latency**: FAISS search O(N) for Flat; acceptable at this scale. Can swap to HNSW/IVF if corpus grows.
- **Batching**: Embedding during index build is batched by SentenceTransformers by default.

## 5. Alternatives Considered
- **OpenAI embeddings**: simpler ops but external API cost and dependency.
- **BM25**: robust for exact term match; considered for hybrid in roadmap.
- **Docstore (Chroma/Weaviate)**: heavier dependency; FAISS + JSONL keeps portability high.

## 6. Risks & Mitigations
- **Docs structure changes** → Re-run ingestion; extraction is resilient and source URLs are stored.
- **Legal/ToS** → Respect robots and site terms; attribute sources; do not republish wholesale.
- **Hallucinations** → System prompt forces “answer only from context”; return citations; set min-score threshold (optional extension).
