# Quick Start Context Block

```markdown
I'm building a Workato RAG Email Response System that processes 750 emails/day, automatically responding to 50-100 customer queries using context from a Google Drive document library. 

Current state:
- Have 2 custom Workato SDK connectors: RAG_Utils and Vertex_AI
- Need to add Google Drive integration for document processing
- Using Google Vertex AI for embeddings and vector search
- Architecture uses 3-stage email filtering (750→150→100→50 responses)

Tech stack: Workato platform, Google Vertex AI (Gemini models, Vector Search, text-embedding-004), Google Drive, Gmail

Key constraints:
- No domain-wide delegation available
- Cost target: <$2/day
- Response time: <15 seconds per email
- Using 2 service accounts (operations/admin)
```
