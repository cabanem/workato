# Details for Data Contract Updates

## Specific Contract Updates Required

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

---

# Use Cases Driving Change

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

---
