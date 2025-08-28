# Crawl the Workato Connector SDK and Package Content

**Objective**: Crawl each page under `/developing-connectors/sdk` &rarr; Normalize content to markdown &rarr; Chunk and index content (for RAG)

**Constraint**: Content is spread across several pages and sections

## Solution (proof of concept)

1. Run script, `crawl_workato_sdk.py`
```bash
pip install requests beautifulsoup4 trafilatura
python crawl_workato_sdk.py
```

2. Chunk content
```bash
python chunk_jsonl.py
```