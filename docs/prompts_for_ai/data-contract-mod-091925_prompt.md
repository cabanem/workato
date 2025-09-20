# Prompt to request updates to data contracts

### Attachment

- Existing contracts document

### Prompt

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

## Validation checklist

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
