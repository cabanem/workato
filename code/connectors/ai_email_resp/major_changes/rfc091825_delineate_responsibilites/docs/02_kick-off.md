# Getting Started

## **Week 1: Proof of Concept (Low Risk)**

### **Day 1-2: Set Up Test Environment**
1. **Clone both connectors** to test versions:
   ```ruby
   RAG_Utils_v2_test
   Vertex_AI_v2_test
   ```

2. **Create a test project/folder** in Workato for isolated testing

3. **Pick ONE use case** to validate the approach:
   - Recommend: Email classification (uses both connectors)
   - Has Data Tables, rules, and AI components

### **Day 3-4: Build Minimal Contract Implementation**
Add these test methods to validate the contract approach:

```ruby
# In RAG_Utils_v2_test, add:
methods: {
  # ... existing methods ...
  
  # Contract validator (simple version)
  validate_contract: lambda do |data, type|
    required = {
      'cleaned_text' => ['text', 'metadata'],
      'classification_request' => ['text', 'classification_mode', 'categories']
    }[type]
    
    missing = required - data.keys
    error("Missing required fields: #{missing}") if missing.any?
    data
  end,
  
  # New preparation action
  prepare_for_vertex: lambda do |connection, input|
    output = {
      'text' => call('process_email_text', {'email_body' => input['text']})['cleaned_text'],
      'metadata' => {
        'original_length' => input['text'].length,
        'cleaned_length' => output['text'].length,
        'processing_applied' => ['email_clean']
      }
    }
    call('validate_contract', output, 'cleaned_text')
  end
}
```

### **Day 5: Create Test Recipe**
Build a single recipe that tests the new flow:

```
Recipe: Email Classification Test v2
1. Trigger: Manual (with test email)
2. RAG_Utils_v2: clean_email_text
3. RAG_Utils_v2: evaluate_email_by_rules (pattern matching)
4. Decision: If no pattern match
   4a. RAG_Utils_v2: prepare_for_vertex
   4b. Vertex_v2: send_messages (for classification)
5. RAG_Utils_v2: validate_llm_response
6. Log results for comparison
```

## **Week 2: Validate & Measure**

### **Performance Testing**
Run the test recipe with 10 sample emails and measure:
- Processing time per step
- Token usage
- Error handling
- Contract validation success

### **Create Comparison Metrics**
```ruby
metrics = {
  old_approach: {
    actions_used: 2,
    avg_time_ms: X,
    token_cost: Y
  },
  new_approach: {
    actions_used: 4,
    avg_time_ms: X+?,
    token_cost: Y,
    benefits: ["clearer flow", "reusable prep", "better testing"]
  }
}
```

## **Week 3: Build Core Components**

Based on validation results, implement priority changes:

### **Priority 1: Remove Vertex Data Tables Dependency**
```ruby
# In Vertex_AI_v2_test
# Comment out or remove:
- All workato_datatable methods
- categorize_text's table reading logic
- Connection fields for Workato API
```

### **Priority 2: Create New Classification Action**
```ruby
# In Vertex_AI_v2_test
actions: {
  ai_classify: {
    title: "AI Classify Text",
    description: "Pure AI classification without rules",
    
    input_fields: lambda do
      [
        { name: "text", optional: false },
        { name: "categories", type: "array", of: "object",
          properties: [
            { name: "key" },
            { name: "description" }
          ]
        },
        { name: "model", pick_list: :available_text_models }
      ]
    end,
    
    execute: lambda do |connection, input|
      # Use existing prompt building but simplified
      prompt = "Classify this text into one of these categories: " \
              "#{input['categories'].map { |c| c['key'] }.join(', ')}"
      # Call existing Gemini infrastructure
    end
  }
}
```

### **Priority 3: Add Migration Warnings**
```ruby
# In Vertex categorize_text action
execute: lambda do |connection, input|
  # Add non-breaking warning
  puts "WARNING: categorize_text will be deprecated in v2.0. " \
       "Consider using RAG_Utils for rule-based or ai_classify for AI classification"
  
  # Continue with existing logic
  # ...
end
```

## **Week 4: Documentation & Rollout**

### **Create Migration Guide**
Simple markdown doc with:
1. Why the change
2. Before/after examples
3. Benefits observed
4. Migration checklist

### **Update Critical Recipes**
Start with lowest-risk recipes:
1. Test/development recipes first
2. Staging recipes after 1 week
3. Production after validation

## **Decision Gate**

After Week 4, evaluate:

### **Go/No-Go Criteria**
```ruby
decision_criteria = {
  proceed_if: [
    "Performance impact < 10%",
    "No data loss in test recipes",
    "Contracts validated successfully",
    "Team understands new pattern"
  ],
  
  abort_if: [
    "Performance degradation > 25%",
    "Contract validation failures > 10%",
    "Unexpected complexity discovered"
  ],
  
  modify_if: [
    "Performance impact 10-25%",
    "Minor contract adjustments needed",
    "Some patterns need refinement"
  ]
}
```

## **Quick Start Checklist**

□ Clone connectors to test versions  
□ Create isolated test project  
□ Add contract validation method  
□ Build one test recipe  
□ Run 10 test cases  
□ Measure performance impact  
□ Document findings  
□ Make go/no-go decision  

## **First Commit**

1. Export both connector JSON/Ruby files
2. Create git repo with structure:
   ```
   /connectors
     /rag_utils
       - v1.0_current.rb
       - v2.0_proposed.rb
     /vertex
       - v1.0_current.rb
       - v2.0_proposed.rb
   /contracts
     - data_contracts.md
   /migration
     - migration_map.md
     - test_recipes.md
   ```
3. First change: Add the contract validator to RAG_Utils
