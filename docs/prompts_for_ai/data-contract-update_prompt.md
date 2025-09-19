# Content for Requesting Data Contract Updates

## 1. Initial Request Template

```markdown
I need to update data contracts for my Workato RAG Email Response System. 

Current situation:
- Have existing data contracts for RAG_Utils ↔ Vertex AI communication
- Need to add contracts for Google Drive document processing
- Must maintain backward compatibility with existing integrations
- Need contracts for new document pipeline workflows

Changes needed:
- Add Google Drive file operations contracts
- Update embedding contracts for document metadata
- Add vector index management contracts
- Enhance batch processing for document workflows
- Add document chunking and processing contracts

Please review and update the contracts while maintaining backward compatibility.
```

## 2. Current Data Contracts to Share

Attach the existing data contracts document

```markdown
These contracts currently cover:
1. Text Preparation (RAG → Vertex)
2. Embeddings (RAG ↔ Vertex)
3. Classification (RAG ↔ Vertex)
4. Prompt Building (RAG → Vertex)
5. Vector Search (RAG ↔ Vertex)
6. Validation (Internal RAG)
7. Error Handling (Both)
8. Batch Processing (RAG → Vertex)
```

## 3. New Requirements Document

```markdown
# New Contract Requirements for Drive Integration

## Document Processing Pipeline
Need contracts for:
- Google Drive → RAG: Document fetching and content extraction
- RAG → RAG: Document chunking with metadata preservation
- RAG → Vertex: Batch embedding with document tracking
- Vertex → RAG: Vector index upsert operations

## Specific Data Flows

### 1. Document Ingestion Flow
```
Drive API → Fetch document → Extract text → Generate metadata → 
Chunk text → Generate embeddings → Store in vector index
```

### 2. Query Flow Enhancement
```
User query → Generate query embedding → Search vector index (with document filters) →
Retrieve relevant chunks → Build RAG prompt → Generate response
```

## Technical Constraints
- Google Drive file IDs must be preserved throughout pipeline
- Chunk IDs must be traceable back to source documents
- Metadata must include: file_id, file_name, chunk_index, checksum
- Support batch operations up to 100 documents
- Maintain change detection via checksums

## New Operations Needing Contracts

1. **list_drive_files**
   - Input: folder_id, modified_after, mime_types
   - Output: array of files with metadata

2. **fetch_drive_file**
   - Input: file_id, export_format
   - Output: text_content, metadata, checksum

3. **batch_fetch_drive_files**
   - Input: array of file_ids
   - Output: successful_files[], failed_files[]

4. **process_document_for_rag**
   - Input: document_content, chunk_config
   - Output: chunks[], document_metadata

5. **upsert_index_datapoints**
   - Input: index_id, datapoints[]
   - Output: success_count, failed_datapoints[]
```

## 4. Specific Changes Needed

```markdown
# Specific Contract Updates Required

## 1. Update Text Preparation Contract
ADD to metadata:
- source_type: add "drive_file" option
- source_metadata object with file_id, file_name, mime_type, checksum

## 2. Update Embedding Request Contract
ADD to text metadata:
- file_id (string)
- file_name (string)
- chunk_total (integer)
- document_checksum (string)

ADD batch_config object:
- max_batch_size (integer, default: 25)
- retry_failed (boolean)
- skip_existing (boolean)

## 3. Update Vector Search Contract
ADD document_filters:
- file_ids (array)
- file_types (array)
- modified_after (datetime)

ADD to response:
- document_groups (grouped results by source document)
- adjacent_chunks (for context expansion)

## 4. New Contract: Document Processing
CREATE contract for:
- Document content from Drive
- Document chunking request/response
- Document metadata structure

## 5. New Contract: Vector Index Operations
CREATE contract for:
- Index upsert request/response
- Batch upsert with error handling
- Index statistics response
```

## 5. Use Cases Driving Changes

```markdown
# Use Cases Requiring Contract Updates

## Use Case 1: Initial Document Loading
As a system admin, I need to:
1. Connect to a Google Drive folder
2. Fetch all PDF and Google Docs
3. Process them into chunks
4. Generate embeddings
5. Store in vector index

## Use Case 2: Incremental Updates
As the system, I need to:
1. Check for modified documents every 6 hours
2. Detect changes via checksums
3. Re-process only changed documents
4. Update vector index incrementally

## Use Case 3: Email Response with Document Context
As the system responding to emails, I need to:
1. Generate query embedding from email
2. Search vector index with document filtering
3. Retrieve relevant chunks with metadata
4. Know which document each chunk came from
5. Build context-aware response

## Use Case 4: Batch Document Processing
As a system processing many documents, I need to:
1. Process up to 100 documents in parallel
2. Handle partial failures gracefully
3. Track which documents succeeded/failed
4. Retry failed documents
```

## 6. Complete Request for New Chat
Attach:
- Existing contracts document

```markdown
I need to update data contracts for my Workato RAG Email Response System to support Google Drive document processing.

Context:
- Building automated email response system using RAG
- Have existing RAG_Utils and Vertex AI connectors with data contracts
- Adding Google Drive integration for document source
- Need to maintain backward compatibility

Current contracts cover: text preparation, embeddings, classification, prompts, vector search, validation, errors, and batch processing.

New requirements:
1. Document fetching from Google Drive
2. Document chunking with metadata preservation  
3. Batch embedding with document tracking
4. Vector index management
5. Enhanced search with document filtering

Specific changes needed:
- Add "drive_file" as source_type
- Add file metadata tracking throughout pipeline
- Add document processing contracts
- Add vector index operation contracts
- Enhance batch processing for documents
- Update vector search for document filtering

Please provide updated contracts that:
1. Maintain backward compatibility
2. Add new contracts for Drive operations
3. Highlight what changed from original
4. Include usage examples for new workflows
```

## 7. Validation Checklist

After receiving updated contracts, validate:

```markdown
□ All original required fields preserved
□ New fields are optional or in new contracts
□ Drive file_id tracked through entire pipeline
□ Chunk-to-document mapping maintained
□ Batch operations properly defined
□ Error contracts handle Drive-specific errors
□ Vector search supports document filtering
□ Change detection via checksums supported
□ Examples provided for document pipeline
□ Backward compatibility confirmed
```
