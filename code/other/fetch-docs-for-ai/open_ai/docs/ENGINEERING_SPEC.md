# Engineering Specification

## 1. Codebase Layout
```
src/
  config.py                # env + defaults
  ingest/
    crawl.py               # crawl + extract main content to JSONL
    chunk.py               # chunking into token-aware pieces
  index/
    embedder.py            # SentenceTransformers interface (BGE)
    faiss_store.py         # FAISS + metadata file store
    build_index.py         # end-to-end index creation
  query/
    retriever.py           # embeds query, FAISS search, optional re-rank
    reranker.py            # cross-encoder reranker (optional)
  llm/
    provider.py            # prompt builder + LLM provider abstraction
  api/
    server.py              # FastAPI app exposing POST /ask
  scripts/
    ingest_and_index.py    # orchestration for ingestion + indexing
    ask.py                 # CLI to query the index
```

## 2. Interfaces & Contracts
### 2.1 Ingestion
- **Input**: `START_URLS`, crawl scope prefixes.
- **Output**: `data/jsonl/workato_sdk_pages.jsonl` with `id,url,title,markdown`.

### 2.2 Chunking
- **Input**: pages JSONL.
- **Output**: `data/jsonl/workato_sdk_chunks.jsonl` with `id,url,text`.

### 2.3 Index
- **Input**: chunks JSONL.
- **Output**: `data/index/workato_sdk.faiss`, `workato_sdk_meta.jsonl`, `workato_sdk_ids.json`.

### 2.4 Retrieval
- **Input**: query string.
- **Output**: list of contexts `{id,url,text,score}`; size configurable (FINAL_K).

### 2.5 Answering
- **Input**: user query + contexts.
- **Output**: natural language answer, citations with `n,url,score`.

### 2.6 API
- **Endpoint**: `POST /ask`
- **Request**: `{ "query": "text", "k": 8 }`
- **Response**:
```json
{
  "query": "How do I publish a connector?",
  "answer": "…",
  "citations": [{"n":1,"url":"https://…","score":0.78}, …],
  "contexts": [{"n":1,"url":"https://…","score":0.78}, …]
}
```

## 3. Configuration (env)
- `START_URLS` (comma-separated)
- `DATA_DIR` (default `./data`)
- `EMBEDDING_MODEL` (default `BAAI/bge-small-en-v1.5`)
- `RERANK` (true/false)
- `LLM_PROVIDER` (`openai`|`none`), `OPENAI_API_KEY`, `OPENAI_MODEL`, `OPENAI_BASE_URL`
- Retrieval knobs: `TOP_K`, `FINAL_K`
- Chunking knobs: `MAX_TOKENS`, `OVERLAP`

## 4. Dependencies
- `requests`, `beautifulsoup4`, `trafilatura`, `sentence-transformers`, `faiss-cpu`, `fastapi`, `uvicorn`, `tiktoken`.

## 5. Error Handling
- HTTP fetch failures → log and continue; page skipped.
- Extraction returns empty → record stub, continue.
- Missing API key when `LLM_PROVIDER=openai` → fallback Noop model; respond with stub answer.
- FAISS index not found on server start → 500 with clear message.
