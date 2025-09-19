# Workato RAG Email Response System

## Detailed Context for Technical Discussion

### Project Overview
```markdown
Project: Automated RAG Email Response System on Workato
Scale: 750 emails/day → 50-100 automated responses
Objective: Automatically respond to customer emails using RAG from document library

Architecture:
1. Email Triage: 3-stage filtering (rules → AI classification → RAG)
2. Document Processing: Google Drive → chunking → embeddings → vector index
3. Response Generation: Query → vector search → context retrieval → LLM response
4. Monitoring: Performance tracking, cost optimization, cache management

Current Implementation Status:
✅ RAG_Utils connector with text processing, chunking, validation
✅ Vertex AI connector with embeddings, LLM, and base vector search
✅ Data contracts defined for all inter-connector communication
❌ Google Drive integration (in progress)
❌ Document processing pipeline recipes
❌ Production monitoring
```

### Technical Components

```markdown
Existing Connectors:
1. RAG_Utils (clone_rag_utils.rb)
   - smart_chunk_text, clean_email_text, calculate_similarity
   - prepare_embedding_batch, build_rag_prompt, validate_llm_response
   - classify_by_pattern (rule-based classification)

2. Vertex AI (clone_vertex.rb) 
   - generate_embeddings (batch), generate_embedding_single
   - send_messages (Gemini), ai_classify (AI classification)
   - find_neighbors (vector search), upsert_index_datapoints
   - OAuth2 and service account authentication

Required Google APIs:
- Vertex AI API (enabled)
- Google Drive API (needs enabling)
- Vector Search index (needs deployment)

Service Account Permissions Needed:
- aiplatform.user, storage.objectViewer (operations account)
- aiplatform.indexes.update (admin account)
- drive.readonly (for document access)
```

### Work in Progress

```markdown
Currently implementing Google Drive integration:

New Actions Needed:
1. fetch_drive_file - Get single file content
2. list_drive_files - Monitor folder changes  
3. batch_fetch_drive_files - Bulk processing
4. monitor_drive_changes - Incremental updates
5. test_connection - Validate all APIs

Data Contracts Updated For:
- Document processing workflows
- Drive file metadata
- Batch embeddings with document tracking
- Vector search with document filtering
```

### Key Decisions & Constraints

```markdown
Constraints:
- Cannot use domain-wide delegation for service accounts
- Must use OAuth2 or share files directly with service account
- Cost limit: $2/day (~$60/month)
- Workato plan limitations on email volume

Design Decisions:
- Use Gemini Flash for classification (cheaper than Pro)
- Batch embeddings in groups of 25
- Cache responses for FAQ-style questions (30% hit rate target)
- 3-stage email filter to minimize API calls
- Chunk size: 1000 tokens with 100 token overlap

Performance Targets:
- Email triage: <1 second
- Classification: <5 seconds  
- RAG response: <30 seconds
- Index updates: Every 6 hours
```

### Files to Share in New Chat

```markdown
Key Files:
1. Project Objectives document (complete requirements)
2. clone_vertex.rb (Vertex AI connector)
3. clone_rag_utils.rb (RAG Utilities connector)
4. Data Contracts document (updated version)

If discussing specific implementation:
- Share the relevant connector code
- Include error messages/logs if debugging
- Provide sample data structures if testing
```

### Specific Context by Use Case

#### For Implementation Help:
```markdown
"I need help implementing Google Drive integration for my Workato RAG Email Response System. I have existing Vertex AI and RAG_Utils connectors, and need to add actions to fetch documents from Drive, process them into chunks, generate embeddings, and store in a vector index. Using OAuth2 authentication, not domain-wide delegation."
```

#### For Debugging:
```markdown
"I'm debugging a Workato custom connector for a RAG system using Google Vertex AI. [Describe specific error]. The connector uses OAuth2 for Drive access and service account for Vertex AI. Here's the relevant code section: [paste code]"
```

#### For Architecture Review:
```markdown
"I'd like review of my RAG Email Response System architecture: 750 emails/day filtered down to 50-100 automated responses using Google Vertex AI embeddings and vector search. Using Workato platform with custom SDK connectors. Current challenge: [specific issue]"
```

#### For Optimization:
```markdown
"Need to optimize a Workato RAG pipeline processing 750 emails/day with <$2/day budget. Using Gemini models for classification and generation, text-embedding-004 for embeddings. Current bottleneck: [describe]. How can I improve [performance/cost/accuracy]?"
```

### Quick Reference Commands

```ruby
# Test Drive connection
Vertex_AI.test_connection({
  test_vertex_ai: true,
  test_drive: true,
  verbose: true
})

# Process single document
doc_result = RAG_Utils.process_document_for_rag({
  document_content: file_content,
  file_path: "document.pdf",
  chunk_size: 1000
})

# Generate embeddings
embedding_result = Vertex_AI.generate_embeddings({
  batch_id: "batch_001",
  texts: chunks,
  model: "publishers/google/models/text-embedding-004"
})
```
