# New Contract Requirements for Drive Integration

## Document Processing Pipeline

Need contracts for:
- Google Drive → RAG: Document fetching and content extraction
- RAG → RAG: Document chunking with metadata preservation
- RAG → Vertex: Batch embedding with document tracking
- Vertex → RAG: Vector index upsert operations

---

## Specific Data Flows

### 1. Document Ingestion Flow

`Drive API → Fetch document → Extract text → Generate metadata → Chunk text → Generate embeddings → Store in vector index`

### 2. Query Flow Enhancement

```
User query → Generate query embedding → Search vector index (with document filters) →
Retrieve relevant chunks → Build RAG prompt → Generate response
```

---

## Technical Constraints
- Google Drive file IDs must be preserved throughout pipeline
- Chunk IDs must be traceable back to source documents
- Metadata must include: file_id, file_name, chunk_index, checksum
- Support batch operations up to 100 documents
- Maintain change detection via checksums

---

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

---

## Summary

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
