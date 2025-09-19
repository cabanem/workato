# Data Contracts 

Connectors: **RAG Utilities**, **Vertex AI**

--- 

## 1. Text Preparation Contracts

### RAG &rarr; Vertex: Cleaned Text
```ruby
{
  # Required fields
  "text": "string",                    # Cleaned/processed text, max 32k tokens
  "metadata": {
    "original_length": "integer",      # Pre-cleaning character count
    "cleaned_length": "integer",       # Post-cleaning character count
    "processing_applied": ["array"],   # ["remove_signatures", "normalize_whitespace"]
    "source_type": "string"            # "email" | "document" | "chat"
  },
  
  # Optional fields
  "extracted_sections": {
    "query": "string",                 # Main question/intent if identifiable
    "context": "string",               # Supporting information
    "entities": ["array"]              # Extracted entities if any
  },

  # Document source tracking
  "source_metadata": {
    "file_id": "string",              # Google Drive file ID
    "file_name": "string",            # Original file name
    "mime_type": "string",            # Original MIME type
    "checksum": "string"              # MD5 for change detection
  }
}
```

## 2. Document Processing Contracts (NEW, 09/19/25)

### Drive &rarr; Document Content
```ruby
{
  # Required fields
  "file_id": "string",                 # Google Drive file ID
  "file_name": "string",               # File name
  "mime_type": "string",               # MIME type
  "text_content": "string",            # Extracted text content
  "checksum": "string",                # MD5 checksum
  "modified_time": "datetime",         # Last modification time
  
  # Optional fields
  "needs_processing": "boolean",       # True for PDFs needing OCR
  "size": "integer",                   # File size in bytes
  "owner_email": "string",             # File owner
  "shared_with": ["array"],            # List of users with access
  "folder_path": "string"              # Parent folder path
}
```

### RAG &rarr; RAG: Document Chunking Request
```ruby
{
  # Required fields
  "document_content": "string",        # Full document text
  "file_path": "string",              # Identifier/path
  
  # Optional fields
  "chunk_config": {
    "chunk_size": "integer",          # Tokens per chunk (default: 1000)
    "chunk_overlap": "integer",       # Overlap tokens (default: 100)
    "preserve_sentences": "boolean",   # Don't break sentences (default: true)
    "preserve_paragraphs": "boolean"   # Try to keep paragraphs (default: false)
  },
  
  "file_metadata": {
    "file_type": "string",            # "pdf" | "docx" | "txt" | "gdoc"
    "file_id": "string",              # Drive file ID
    "checksum": "string"              # For deduplication
  }
}
```

### RAG Response: Chunked Document
```ruby
{
  # Required fields
  "document_id": "string",             # Generated document UUID
  "chunks": [
    {
      "chunk_id": "string",            # "doc_id_chunk_0"
      "chunk_index": "integer",        # Sequential index
      "text": "string",                # Chunk content
      "token_count": "integer",        # Estimated tokens
      "start_char": "integer",         # Start position in original
      "end_char": "integer",           # End position in original
      "metadata": {
        "document_id": "string",
        "file_path": "string",
        "chunk_index": "integer",
        "has_overlap": "boolean",
        "is_final": "boolean"
      }
    }
  ],
  "document_metadata": {
    "file_hash": "string",            # SHA256 of content
    "word_count": "integer",
    "character_count": "integer",
    "estimated_tokens": "integer",
    "language": "string",
    "key_topics": ["array"],
    "created_at": "timestamp"
  },
  "total_chunks": "integer",
  "total_tokens": "integer",
  "ready_for_embedding": "boolean"
}
```

## 3. Embedding Contracts (UPDATE, 09/19/25)

### RAG &rarr; Vertex: Embedding Request (UPDATE, 09/19/25)
```ruby
{
  # Required fields
  "batch_id": "string",                # Unique batch identifier
  "texts": [                           # Array of texts to embed
    {
      "id": "string",                  # Unique identifier (e.g., "doc_123_chunk_0")
      "content": "string",             # Text content, max 8192 tokens
      "metadata": {                    # Metadata to attach to embedding
        "chunk_index": "integer",
        "document_id": "string",
        "source": "string",
        
        # NEW: Document tracking
        "file_id": "string",           # Google Drive file ID
        "file_name": "string",         # Original file name
        "chunk_total": "integer",      # Total chunks in document
        "document_checksum": "string"  # For change detection
      }
    }
  ],
  
  # Optional fields
  "task_type": "string",                # "RETRIEVAL_DOCUMENT" | "RETRIEVAL_QUERY" | etc
  "title": "string",                    # Document title for RETRIEVAL_DOCUMENT
  "model": "string",                    # Override default model
  
  # NEW: Batch processing config
  "batch_config": {
    "max_batch_size": "integer",        # Max items per API call (default: 25)
    "retry_failed": "boolean",          # Retry failed embeddings
    "skip_existing": "boolean"          # Skip if already in index
  }
}
```

### Vertex &rarr; RAG: Embedding Response
```ruby
{
  # Required fields
  "batch_id": "string",                # Matching request batch_id
  "embeddings": [
    {
      "id": "string",                  # Matching input text id
      "vector": ["array of float"],    # Embedding vector
      "dimensions": "integer",         # Vector dimensions (e.g., 768)
      
      # NEW: Preserve full metadata
      "metadata": {}                   # Original metadata from request
    }
  ],
  "model_used": "string",              # "text-embedding-004"
  
  # Optional fields
  "usage": {
    "total_tokens": "integer",
    "characters_processed": "integer",
    
    # NEW: Batch metrics
    "batches_processed": "integer",    # Number of API calls made
    "api_calls_saved": "integer"       # Saved through batching
  },
  
  # Updated error structure for batch processing
  "processing_stats": {
    "successful": "integer",
    "failed": "integer",
    "skipped": "integer"
  },
  
  "errors": [                          # Per-item errors if any
    {
      "id": "string",
      "error": "string",
      "retry_count": "integer"
    }
  ]
}
```

## 4. Vector Index Contracts (NEW, 09/19/25)

### RAG &rarr; Vertex: Index Upsert Request
```ruby
{
  # Required fields
  "index_id": "string",                # "projects/PROJECT/locations/REGION/indexes/INDEX_ID"
  "datapoints": [
    {
      "datapoint_id": "string",        # Unique ID (e.g., "doc_123_chunk_0")
      "feature_vector": ["array"],     # Embedding vector
      
      # Optional metadata filtering
      "restricts": [
        {
          "namespace": "string",        # e.g., "source", "file_type"
          "allowList": ["array"],       # Allowed values
          "denyList": ["array"]         # Denied values
        }
      ],
      
      "crowding_tag": "string"         # For result diversity
    }
  ],
  
  # Optional fields
  "update_mask": "string",             # Fields to update for existing points
  "batch_config": {
    "max_batch_size": "integer",      # Max per request (default: 100)
    "retry_on_failure": "boolean"
  }
}
```

### Vertex &rarr; RAG: Index Upsert Response
```ruby
{
  # Required fields
  "successfully_upserted_count": "integer",
  "total_processed": "integer",
  
  # Optional fields
  "failed_upserts": "integer",
  "failed_datapoints": [
    {
      "datapoint_id": "string",
      "error": "string"
    }
  ],
  
  "index_stats": {
    "index_id": "string",
    "deployed_state": "string",       # "DEPLOYED" | "UNDEPLOYED"
    "total_datapoints": "integer",
    "dimensions": "integer",
    "display_name": "string",
    "updated_time": "datetime"
  }
}
```

## 5. Drive Operations Contracts (NEW, 09/19/25)

### Recipe &rarr; Vertex: List Drive Files Request
```ruby
{
  # Optional fields (all optional for flexibility)
  "folder_id": "string",               # Specific folder to list
  "modified_after": "datetime",        # For incremental processing
  "mime_types": ["array"],             # Filter by MIME type
  "max_results": "integer",            # Limit results (default: 100)
  "query": "string"                    # Custom Drive API query
}
```

### Vertex &rarr; Recipe: List Drive Files Response
```ruby
{
  # Required fields
  "files": [
    {
      "id": "string",                  # File ID
      "name": "string",                # File name
      "mimeType": "string",            # MIME type
      "size": "string",                # Size in bytes
      "modifiedTime": "datetime",     # Last modified
      "parents": ["array"]             # Parent folder IDs
    }
  ],
  "count": "integer",                  # Number of files returned
  
  # Optional fields
  "has_more": "boolean",              # More results available
  "next_page_token": "string"         # For pagination
}
```

### Recipe &rarr; Batch Fetch Files Request
```ruby
{
  # Required fields
  "file_ids": ["array of strings"],    # File IDs to fetch
  
  # Optional fields
  "skip_errors": "boolean",           # Continue on individual failures
  "export_format": "string",          # Export format for Google files
  "include_metadata": "boolean"       # Include extended metadata
}
```

### Vertex &rarr; Recipe: Batch Fetch Files Response
```ruby
{
  # Required fields
  "successful_files": [
    {
      "file_id": "string",
      "file_name": "string",
      "mime_type": "string",
      "text_content": "string",
      "checksum": "string",
      "modified_time": "datetime"
    }
  ],
  "failed_files": [
    {
      "file_id": "string",
      "error": "string"
    }
  ],
  "total_processed": "integer",
  
  # Optional fields
  "success_rate": "float",            # Percentage successful
  "processing_time_ms": "integer"
}
```

### Recipe &rarr; Vertex: Monitor Changes Request
```ruby
{
  # Optional fields
  "page_token": "string",              # From previous run (null for initial)
  "folder_id": "string",               # Specific folder to monitor
  "include_removed": "boolean"         # Track deletions
}
```

### Vertex &rarr; Recipe: Monitor Changes Response
```ruby
{
  # Required fields
  "changes": [
    {
      "fileId": "string",
      "removed": "boolean",
      "file": {                        # Present if not removed
        "id": "string",
        "name": "string",
        "mimeType": "string",
        "modifiedTime": "datetime"
      }
    }
  ],
  "new_page_token": "string",          # Store for next run
  
  # Processed categorization
  "files_added": ["array"],
  "files_modified": ["array"],
  "files_removed": ["array of IDs"]
}
```

## 6. Complete Document Pipeline Contract (NEW, 09/19/25)

### Recipe &rarr; RAG: Process Document for RAG
```ruby
{
  # Required fields
  "document_content": "string",        # Document text
  "file_path": "string",               # File identifier
  
  # Optional fields
  "file_type": "string",               # "pdf" | "docx" | "gdoc" | etc
  "chunk_size": "integer",             # Tokens per chunk
  "chunk_overlap": "integer",          # Overlap tokens
  "generate_embeddings": "boolean",    # Process immediately
  
  "file_metadata": {
    "file_id": "string",               # Drive file ID
    "checksum": "string",              # For deduplication
    "owner": "string",
    "modified_time": "datetime"
  }
}
```

### RAG &rarr; Recipe: Processed Document Response
```ruby
{
  # Required fields
  "document_id": "string",             # Generated document UUID
  "chunks": [                          # Array of processed chunks
    {
      "chunk_id": "string",
      "text": "string",
      "metadata": {}
    }
  ],
  "document_metadata": {               # Full document metadata
    "file_hash": "string",
    "word_count": "integer",
    "estimated_tokens": "integer",
    "key_topics": ["array"]
  },
  "ready_for_embedding": "boolean",
  "total_chunks": "integer",
  "estimated_tokens": "integer"
}
```

## 7. Error Contracts (UPDATED, 09/19/25)

### Standard Error Format (Both Connectors)
```ruby
{
  "error": {
    "code": "string",                   # "INVALID_INPUT" | "QUOTA_EXCEEDED" | "DRIVE_ACCESS_DENIED" | etc
    "message": "string",                # Human-readable message
    "details": {
      "field": "string",                # Error-causing field
      "constraint": "string",           # Description of violated constraint
      "provided": "any",                # Provided content
      "expected": "any",                # Expected content
      
      # NEW: Drive-specific error details
      "file_id": "string",              # For file-specific errors
      "permission_needed": "string"     # Required permission
    },
    "retry_after": "integer",           # Seconds to wait before retry
    "correlation_id": "string",         # For debugging across connectors
    
    # NEW: Batch error tracking
    "batch_context": {
      "batch_id": "string",
      "item_index": "integer",
      "total_items": "integer"
    }
  }
}
```

## 8. Batch Processing Contracts (UPDATED, 09/19/25)

### RAG &rarr; Vertex: Batch Request
```ruby
{
  "batch_id": "string",
  "batch_type": "string",               # "embeddings" | "classifications" | "generations" | "documents"
  "items": ["array"],                   # Array of individual requests
  "batch_config": {
    "max_parallel": "integer",          # Max parallel API calls
    "retry_failed": "boolean",          # Auto-retry failed items
    "partial_success_ok": "boolean",    # Continue if some items fail
    
    # NEW: Document processing specific
    "chunk_documents": "boolean",       # Auto-chunk large documents
    "generate_embeddings": "boolean",   # Generate embeddings inline
    "update_index": "boolean"           # Update vector index inline
  },
  
  # NEW: Source tracking
  "source": {
    "type": "string",                  # "drive" | "upload" | "api"
    "folder_id": "string",             # For Drive sources
    "batch_timestamp": "datetime"
  }
}
```

# OLD CONTRACTS
## . Classification Contracts

### RAG &rarr; Vertex: Classification Request
```ruby
{
  # Required fields
  "text": "string",                     # Text to classify
  "classification_mode": "string",      # "rules" | "ai" | "hybrid"
  
  # For AI classification
  "categories": [
    {
      "key": "string",                  # Category identifier
      "description": "string",          # Optional description/rule
      "examples": ["array"]             # Optional examples
    }
  ],
  
  # Optional fields
  "options": {
    "return_confidence": "boolean",     # Default: true
    "return_alternatives": "integer",   # Top N alternatives, default: 0
    "temperature": "float",             # Model temperature, default: 0
    "max_tokens": "integer"             # Response limit
  }
}
```

### Vertex &rarr; RAG: Classification Response
```ruby
{
  # Required fields
  "selected_category": "string",        # Chosen category key
  "confidence": "float",                # 0.0 to 1.0
  
  # Optional fields
  "alternatives": [
    {
      "category": "string",
      "confidence": "float"
    }
  ],
  "reasoning": "string",                # Model's explanation if requested
  "usage": {
    "prompt_tokens": "integer",
    "completion_tokens": "integer"
  }
}
```


## . Prompt Contracts

### RAG &rarr; Vertex: Prepared Prompt
```ruby
{
  # Required fields
  "prompt_type": "string",              # "rag_response" | "analysis" | "generation"
  "formatted_prompt": "string",         # Complete formatted prompt
  
  # Optional fields
  "system_instruction": {
    "role": "model",
    "parts": [{"text": "string"}]
  },
  
  "context_documents": [                # For RAG responses
    {
      "id": "string",
      "content": "string",
      "relevance_score": "float",
      "metadata": {}
    }
  ],
  
  "generation_config": {
    "temperature": "float",             # 0.0 to 2.0
    "maxOutputTokens": "integer",       # Max response tokens
    "topK": "integer",                  # Top K sampling
    "topP": "float",                    # Top P sampling
    "responseMimeType": "string"        # "text/plain" | "application/json"
  },
  
  "response_schema": {                  # For structured output
    "type": "object",
    "properties": {},
    "required": ["array"]
  },
  
  "safety_settings": [
    {
      "category": "string",
      "threshold": "string"
    }
  ]
}
```

### Vertex &rarr; RAG: Generation Response
```ruby
{
  # Required fields
  "content": "string",                  # Generated text
  "finish_reason": "string",            # "STOP" | "MAX_TOKENS" | "SAFETY" | etc
  
  # Optional fields
  "structured_data": {},                # If JSON response requested
  
  "safety_ratings": {
    "sexually_explicit": "string",      # "NEGLIGIBLE" | "LOW" | "MEDIUM" | "HIGH"
    "hate_speech": "string",
    "harassment": "string",
    "dangerous_content": "string"
  },
  
  "usage": {
    "promptTokenCount": "integer",
    "candidatesTokenCount": "integer",
    "totalTokenCount": "integer"
  },
  
  "model_version": "string",
  "response_id": "string"
}
```

## 5. Vector Search Contracts

### RAG &rarr; Vertex: Vector Search Request
```ruby
{
  # Required fields
  "query_vector": ["array of float"],   # Query embedding
  "index_endpoint": {
    "host": "string",                   # "1234.us-central1.vdb.vertexai.goog"
    "endpoint_id": "string",            # Index endpoint ID
    "deployed_index_id": "string"       # Deployed index ID
  },
  
  # Optional fields
  "search_params": {
    "neighbor_count": "integer",        # k value, default: 10
    "return_full_datapoint": "boolean", # Include vectors in response
    
    "filters": {                        # Metadata filtering
      "restricts": [
        {
          "namespace": "string",
          "allowList": ["array"],
          "denyList": ["array"]
        }
      ],
      "numericRestricts": [
        {
          "namespace": "string",
          "op": "string",               # "EQUAL" | "LESS" | "GREATER" | etc
          "value": "number"
        }
      ]
    }
  }
}
```

### Vertex &rarr; RAG: Vector Search Response
```ruby
{
  # Required fields
  "neighbors": [
    {
      "id": "string",                   # Document/chunk ID
      "distance": "float",              # Distance metric
      "datapoint": {                    # If return_full_datapoint=true
        "featureVector": ["array"],
        "restricts": [],
        "numericRestricts": []
      }
    }
  ],
  
  # Optional fields
  "query_id": "string",
  "search_time_ms": "integer"
}
```

## 6. Validation Contracts

### RAG &rarr; RAG: Validation Request
```ruby
{
  # Required fields
  "response": "string",                 # LLM response to validate
  "original_query": "string",           # Original user question
  
  # Optional fields
  "context_provided": ["array"],        # Context documents used
  "expected_format": "string",          # "json" | "email" | "list" | etc
  "validation_rules": [
    {
      "rule_type": "string",            # "contains" | "not_contains" | "length"
      "rule_value": "any"
    }
  ]
}
```

### RAG Response: Validation Result
```ruby
{
  # Required fields
  "is_valid": "boolean",
  "confidence_score": "float",          # 0.0 to 1.0
  
  # Optional fields
  "issues_found": ["array"],
  "requires_human_review": "boolean",
  "validation_details": {
    "query_overlap": "float",
    "response_length": "integer",
    "format_valid": "boolean"
  }
}
```



## Usage Patterns

### Email Response Pipeline
```ruby
# 1. Email arrives => RAG cleans
rag_output = {
  "text": "cleaned email content",
  "metadata": { "source_type": "email" }
}

# 2. RAG evaluates => Vertex classifies if needed
classification_request = {
  "text": rag_output["text"],
  "classification_mode": "ai",
  "categories": [...]
}

# 3. RAG builds prompt => Vertex generates
prompt_request = {
  "prompt_type": "rag_response",
  "formatted_prompt": "...",
  "context_documents": [...]
}

# 4. Vertex responds => RAG validates
validation_request = {
  "response": vertex_response["content"],
  "original_query": original_email["text"]
}
```
---



# Context for New Chat: Workato RAG Email Response System

## Quick Start Context Block
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
