# Ask-the-Docs System

## 1 - At a Glance
### Functional Objectives
- Crawl the docs section (robots-aware, incremental)
- Extract clean Markdown and metadata
- Chunk the content (token-aware, code-block friendly)
- Index chunks in FAISS with SentenceTransformers embeddings
- Retrieve and (optionally) re-rank candidates
- Generate answers using LLM
- Serve a simple FastAPI endpoint `POST / ask`, returning answers with citations

### Technical decisions
- Crawler: `requests`, `BeautifulSoup`, `trafilatura`
- Embeddings: `BAAI/bge-small-en-v1.5`
- Vector DB: `faiss-cpu` (cosine via inner product on normalized vectors)
- Re-ranker: `cross-encoder` / `ms-macro-MiniLM-L-6-v2`
- API: `FastAPI` and `uvicorn`
- LLM: plugable

### Key properties
- Incremental - honors `ETag` / `Last-Modified` (skips unchanged pages)
- Boundary-aware chunking - avoids splitting within ``` code fences and prefers boundary headers
- Transparent citations - each answer is cite-bound, inclusive of URL

### Project Layout
```
workato-rag/
├─ README.md
├─ requirements.txt
├─ .env.example
├─ data/
│  ├─ raw_html/           # cached HTML
│  ├─ md/                 # extracted Markdown
│  ├─ jsonl/              # page-level and chunk-level corpora
│  └─ index/              # faiss + metadata store
└─ src/
   ├─ config.py
   ├─ ingest/
   │  ├─ crawl.py
   │  └─ chunk.py
   ├─ index/
   │  ├─ embedder.py
   │  ├─ faiss_store.py
   │  └─ build_index.py
   ├─ query/
   │  ├─ retriever.py
   │  └─ reranker.py
   ├─ llm/
   │  └─ provider.py
   ├─ api/
   │  └─ server.py
   └─ scripts/
      ├─ ingest_and_index.py
      └─ ask.py
```

## 2 - Setup
### `requirements.txt`
```
```

### `.env` (example)
```
```

## 3 - Configuration
**`src/config.py`**
```python

```

## 4 - Ingestion (crawl > extract > page JSONL)
**`src/ingest/crawl.py`**
```python
```