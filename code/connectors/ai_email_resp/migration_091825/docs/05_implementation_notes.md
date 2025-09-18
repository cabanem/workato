# Connector Migration Implementation Guide

## Overview
This document provides step-by-step instructions for migrating RAG_Utils and Vertex AI connectors to achieve clean separation between preparation (RAG_Utils) and AI (Vertex) layers.

---

## Part 1: RAG_Utils Connector Modifications

### Task 1: Add Contract Validation Infrastructure
**Location:** Methods section, after existing helper methods (~line 1500)  
**Action:** Add new validation method

**Prompt for AI/Developer:**
```
Add a new method called 'validate_contract' to the RAG_Utils connector methods section. This method should:
1. Accept parameters: connection, data, and contract_type
2. Define contracts for: 'cleaned_text', 'embedding_request', 'classification_request', and 'prompt_request'
3. Validate required fields based on contract type
4. Return the data if valid, error if not
Place this after the existing helper methods around line 1500.
```

### Task 2: Rename Email Rule Evaluation
**Location:** Action around line 871  
**Action:** Rename action and update metadata

**Prompt for AI/Developer:**
```
Find the action 'evaluate_email_by_rules' in RAG_Utils connector.
Rename it to 'classify_by_pattern' with:
- New title: 'Classify by pattern matching'
- New subtitle: 'Pattern-based classification without AI'
- New description: 'Evaluate text against pattern rules from standard library or Data Tables'
Keep all other fields (help, config_fields, input_fields, output_fields, execute) unchanged.
```

### Task 3: Create Text Preparation Action
**Location:** After classify_by_pattern action (~line 1050)  
**Action:** Add new action

**Prompt for AI/Developer:**
```
Create a new action called 'prepare_for_ai' in RAG_Utils after the classify_by_pattern action. This action should:

Input fields:
- text (required, text-area)
- source_type (required, select: email/document/chat/general)
- task_type (required, select: classification/generation/analysis/embedding)
- options (optional object with remove_pii and max_length)

Processing:
- Use existing process_email_text for email source_type
- Build contract-compliant output with text and metadata
- Validate output using the validate_contract method
- Return cleaned_text contract format
```

### Task 4: Update Embedding Batch Formatter
**Location:** format_embeddings_batch action (~line 245)  
**Action:** Replace with new implementation

**Prompt for AI/Developer:**
```
Replace the 'format_embeddings_batch' action with a new 'prepare_embedding_batch' action that:
1. Accepts texts array with id, content, title, metadata
2. Adds batch_id generation
3. Includes task_type selection (RETRIEVAL_DOCUMENT/QUERY/SEMANTIC_SIMILARITY)
4. Returns embedding_request contract format
5. Validates output with validate_contract method
```

### Task 5: Mark Vertex-Specific Actions as Deprecated
**Location:** to_vertex_datapoints action (~line 1100)  
**Action:** Add deprecation warning

**Prompt for AI/Developer:**
```
In the 'to_vertex_datapoints' action:
1. Add field: deprecated: 'This action will be replaced by format_vector_datapoints in v2.0'
2. Add to execute block start: puts "DEPRECATION WARNING: to_vertex_datapoints will be replaced by format_vector_datapoints in v2.0"
```

---

## Part 2: Vertex AI Connector Modifications

### Task 6: Remove Data Tables Integration
**Location:** Multiple locations  
**Action:** Delete methods and fields

**Prompt for AI/Developer:**
```
Remove all Workato Data Tables integration from Vertex AI connector:

1. DELETE these methods (around lines 1800-2000):
   - ensure_workato_api!
   - workato_api_headers
   - workato_api_base
   - list_datatables
   - list_datatable_columns
   - fetch_datatable_rows
   - cached_table_rows
   - load_categories_from_table

2. DELETE from connection fields (around line 50):
   - workato_api_host field
   - workato_api_token field

3. DELETE from pick_lists section:
   - workato_datatables
   - workato_datatable_columns
```

### Task 7: Create AI Classification Action
**Location:** After categorize_text action (~line 700)  
**Action:** Add new action

**Prompt for AI/Developer:**
```
Create a new action 'ai_classify' in Vertex connector after categorize_text. Requirements:

Input:
- text (required, from RAG_Utils preparation)
- categories array (key and optional description)
- model (required, use available_text_models picklist)
- options object (return_confidence, return_alternatives, temperature)

Output:
- selected_category
- confidence (0.0-1.0)
- alternatives array
- usage metrics

Implementation:
- Build prompt for classification
- Use existing build_base_payload method
- Return classification_response contract format
```

### Task 8: Deprecate Old Categorization
**Location:** categorize_text action (~line 600)  
**Action:** Add deprecation notices

**Prompt for AI/Developer:**
```
Update the 'categorize_text' action in Vertex connector:
1. Add: deprecated: true
2. Change title to: 'Categorize text (DEPRECATED)'
3. Update subtitle: 'Will be removed in v2.0 - Use ai_classify or RAG_Utils::classify_by_pattern'
4. Add to execute start: puts "DEPRECATION WARNING: categorize_text is deprecated. Use RAG_Utils::classify_by_pattern for rules or ai_classify for AI classification"
```

### Task 9: Add Batch Embedding Support
**Location:** generate_embedding action (~line 900)  
**Action:** Replace with batch version

**Prompt for AI/Developer:**
```
Replace 'generate_embedding' with 'generate_embeddings' (plural) that:

Input:
- batch_id (required)
- texts array with id, content, metadata
- task_type (optional)
- model (required, embedding models)

Processing:
- Loop through texts array
- Generate embedding for each
- Collect vectors with IDs

Output:
- batch_id (matching input)
- embeddings array (id, vector, dimensions)
- model_used
- usage statistics

Use existing embedding generation logic but process multiple texts.
```

### Task 10: Update Send Messages for Prepared Input
**Location:** send_messages action  
**Action:** Add contract support

**Prompt for AI/Developer:**
```
Update 'send_messages' action to accept prepared input:
1. Check if input contains 'formatted_prompt' field
2. If yes, use it directly instead of building prompt
3. Keep backward compatibility for existing usage
4. Add comment: "# Accepts prepared prompts from RAG_Utils"
```

---

## Part 3: Testing & Validation

### Task 11: Create Test Recipe
**Recipe Name:** Test_Connector_Migration_v2

**Prompt for Recipe Creation:**
```
Create a Workato recipe that tests the new connector flow:

1. Manual trigger with test email text
2. RAG_Utils: clean_email_text action
3. RAG_Utils: classify_by_pattern (use standard rules)
4. If no match (condition):
   4a. RAG_Utils: prepare_for_ai (source=email, task=classification)
   4b. Vertex: ai_classify with prepared text
5. RAG_Utils: validate_llm_response
6. Logger: Output all results for comparison

Test with 3 sample emails:
- Newsletter (should match pattern)
- Customer inquiry (needs AI)
- Mixed content (tests both paths)
```

### Task 12: Create Integration Test
**Test Name:** Contract_Validation_Test

**Prompt for Test Creation:**
```
Create a test that validates data contracts between connectors:

1. Generate sample data for each contract type
2. Pass through RAG_Utils validation
3. Send to appropriate Vertex action
4. Verify response matches expected contract
5. Log any contract violations

Test cases:
- Valid cleaned_text → ai_classify
- Valid embedding_request → generate_embeddings
- Invalid data → should error appropriately
```

---

## Part 4: Documentation Updates

### Task 13: Update Connector README
**Location:** Both connector documentation

**Prompt for Documentation:**
```
Update the README/documentation for both connectors:

RAG_Utils:
- Add section "Preparation Layer Responsibilities"
- Document all contract formats
- Add examples of preparing data for Vertex
- Include deprecation notices

Vertex AI:
- Add section "AI Layer Responsibilities"
- Document that it expects prepared input
- Remove Data Tables documentation
- Add migration guide from v1 to v2
```

### Task 14: Create Migration Script
**Purpose:** Automate recipe updates

**Prompt for Script Creation:**
```
Create a Ruby script that:
1. Exports all recipes using deprecated actions
2. Lists required changes for each
3. Generates updated recipe JSON
4. Creates rollback versions
5. Provides dry-run and apply modes

Include mappings:
- evaluate_email_by_rules → classify_by_pattern
- categorize_text → prepare_for_ai + ai_classify
- format_embeddings_batch → prepare_embedding_batch
```

---

## Verification Prompts

### Final Validation Prompt:
```
Review both modified connectors and verify:

RAG_Utils Checklist:
□ Has validate_contract method
□ Has classify_by_pattern (renamed)
□ Has prepare_for_ai action
□ Has prepare_embedding_batch
□ All actions use contract validation
□ Deprecation notices added

Vertex AI Checklist:
□ No Data Tables references
□ Has ai_classify action
□ categorize_text marked deprecated
□ Has generate_embeddings (batch)
□ Accepts prepared input
□ All pick_lists work

Integration Checklist:
□ Test recipe runs successfully
□ Contracts validate correctly
□ No circular dependencies
□ Performance acceptable
□ Error handling works
```

### Rollback Prompt (if needed):
```
If migration fails, restore original versions:
1. Revert all code changes
2. Remove new actions
3. Restore original action names
4. Re-add Data Tables integration to Vertex
5. Remove contract validation
6. Update documentation to reflect rollback
```

---

## Quick Reference: Key Changes

| Component | Old | New | Contract |
|-----------|-----|-----|----------|
| Email Classification | `vertex::categorize_text` | `rag::classify_by_pattern` OR `rag::prepare_for_ai` + `vertex::ai_classify` | classification_request |
| Embeddings | `vertex::generate_embedding` | `rag::prepare_embedding_batch` + `vertex::generate_embeddings` | embedding_request |
| Text Prep | Inline in Vertex | `rag::prepare_for_ai` | cleaned_text |
| Validation | Vertex safety only | `rag::validate_ai_response` | validation_result |
| Data Tables | Both connectors | RAG_Utils only | N/A |

---
