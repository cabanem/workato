# Pre-Migration Analysis

## **1. Action-by-Action Migration Analysis**

### **Actions to Move/Refactor**

| Current Location | Action | Decision | Migration Needs |
|-----------------|---------|----------|-----------------|
| **Vertex** | `categorize_text` | Move logic to RAG_Utils | - Rename to `classify_text_by_rules` in RAG_Utils<br>- Keep AI categorization as `ai_classify` in Vertex<br>- Define input/output contract |
| **RAG_Utils** | `build_rag_prompt` | Keep, but enhance | - Add output format for direct Vertex consumption<br>- Include model-specific formatting options |
| **RAG_Utils** | `validate_llm_response` | Keep, but expand | - Add Vertex safety rating integration<br>- Merge with finish_reason validation |
| **Both** | Data Tables methods | Consolidate in RAG_Utils | - Remove from Vertex entirely<br>- Create standard table schemas |

### **New Actions Needed**

```ruby
# RAG_Utils additions:
prepare_vertex_request: {
  # Combines multiple prep steps into Vertex-ready payload
  # Inputs: text, template, embeddings, config
  # Output: Vertex-formatted request body
}

batch_prepare_embeddings: {
  # Prepares multiple texts for embedding generation
  # Handles chunking, metadata, batching
}

# Vertex additions:
batch_generate_embeddings: {
  # Processes prepared batches from RAG_Utils
  # Returns raw embeddings for RAG_Utils formatting
}
```

## **2. Data Flow Contracts**

### **Critical Interfaces to Define**

```ruby
# RAG → Vertex Contract
{
  embedding_request: {
    texts: ['array of prepared strings'],
    task_type: 'RETRIEVAL_DOCUMENT',
    metadata: { source_chunks: ['chunk_ids'] }
  },
  
  prompt_request: {
    system_instruction: 'formatted string',
    user_content: 'formatted string', 
    generation_config: {},
    expected_response_type: 'json|text'
  },
  
  classification_request: {
    text: 'cleaned input',
    categories: ['array'],
    confidence_threshold: 0.7
  }
}

# Vertex → RAG Contract  
{
  embedding_response: {
    embeddings: [[vectors]],
    model_version: 'text-embedding-004',
    token_count: 1234
  },
  
  classification_response: {
    category: 'selected',
    confidence: 0.95,
    alternatives: []
  }
}
```

## **3. Configuration Analysis**

### **Connection Field Conflicts**

Both connectors have overlapping configuration:

| Field | RAG_Utils | Vertex | Resolution |
|-------|-----------|---------|------------|
| `api_token` | Workato API | Remove | Keep in RAG only |
| `environment` | dev/staging/prod | Remove | Keep in RAG only |
| `region` | Not used | Keep | Vertex only |
| `verbose_errors` | Not present | Keep | Add to both |

### **Configuration Migration**
```ruby
# New shared configuration schema
shared_config: {
  error_verbosity: 'normal|verbose',
  retry_strategy: 'exponential|linear',
  cache_ttl: 3600
}
```

## **4. Method Dependencies**

### **Circular Dependency Risks**

Identify methods that might create circular dependencies:

```ruby
# Current problem methods:
RAG_Utils::format_for_vertex_ai  # Knows about Vertex structure
Vertex::load_categories_from_table  # Duplicates RAG functionality

# Solution: Interface methods
RAG_Utils::export_for_ai -> generic format
Vertex::import_from_preparation -> accepts generic
```

## **5. Performance Impact Analysis**

### **Latency Implications**

| Pattern | Current | With Separation | Impact |
|---------|---------|-----------------|--------|
| Email → Classification → Response | 1 action | 2-3 actions | +50-100ms |
| Bulk embedding generation | 1 call | 2 calls | +200ms |
| Template + prompt | Inline | 2 actions | +30ms |

### **Optimization Opportunities**
- Parallel execution where possible
- Batch multiple preparations before AI calls
- Cache preparation results

## **6. Testing Strategy Requirements**

### **Mock Data Structures**
```ruby
# Need to define:
test_fixtures: {
  rag_to_vertex_payload: 'standard format',
  vertex_to_rag_response: 'standard format',
  error_scenarios: ['malformed', 'timeout', 'quota'],
  edge_cases: ['empty', 'oversized', 'special_chars']
}
```

### **Integration Test Scenarios**
1. RAG preparation → Vertex inference → RAG validation
2. Error propagation across connectors
3. Timeout handling between connectors
4. Cache consistency

## **7. Recipe Migration Impact**

### **Breaking Changes**
```ruby
affected_recipes: {
  high_impact: [
    'Email categorization with AI',
    'Document embedding pipeline'
  ],
  low_impact: [
    'Simple text translation',
    'Image analysis'
  ]
}
```

### **Migration Patterns**
```ruby
# Old pattern
Vertex::categorize_text(text, rules_from_table)

# New pattern  
rules = RAG_Utils::load_classification_rules()
prepared = RAG_Utils::prepare_text(text)
Vertex::ai_classify(prepared, rules)
```

## **8. Documentation Requirements**

### **Developer Guides Needed**
1. **Architecture Guide**: Why separation exists
2. **Migration Guide**: Step-by-step for existing recipes
3. **Pattern Library**: Common recipe patterns
4. **API Reference**: Complete input/output specs
5. **Troubleshooting Guide**: Common issues across connectors

### **Inline Documentation**
```ruby
# Each bridging action needs:
help: {
  body: 'This action prepares data for Vertex AI. Output can be passed to Vertex::action_name',
  learn_more_url: 'link/to/pattern/guide'
}
```

## **9. Backward Compatibility**

### **Deprecation Timeline**
- v1.0: Current state
- v1.1: Add new separated actions, deprecation warnings
- v1.2: Hide deprecated actions from UI
- v2.0: Remove deprecated actions

### **Compatibility Shims**
```ruby
# Temporary forwarding actions
categorize_text_legacy: {
  deprecated: true,
  execute: lambda do |connection, input|
    # Auto-forward to new pattern
    rules = call('transform_inline_rules', input['categories'])
    # ... forward to new action
  end
}
```

## **10. Monitoring & Observability**

### **Metrics to Track**
- Cross-connector latency
- Cache hit rates between connectors  
- Error rates at boundaries
- Token usage optimization

### **Debug Enhancements**
```ruby
# Add to both connectors
debug_context: {
  source_connector: 'rag_utils',
  target_connector: 'vertex',
  correlation_id: 'uuid',
  preparation_time: 123,
  inference_time: 456
}
```

## **Next Steps Priority**

- [x] Define exact data contracts
- [x] Create migration guide with examples
- [] Build compatibility shims
4.- [] Test with real recipes
5.- [] Deploy
