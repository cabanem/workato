# Connector Migration Strategy (RAG Utilities, Vertex)

## **Strategy: Clear Separation of Concerns**

### 1. **Text Classification - Choose One Path**
**Current overlap**: RAG_Utils has `evaluate_email_by_rules`, Vertex has `categorize_text`

**Proposed Modification(s)**: 
- **Keep** RAG_Utils' `evaluate_email_by_rules` for pattern-based filtering
- **Remove** or **rename** Vertex's `categorize_text` to `ai_categorize_text`
- **Clear distinction**: Pattern matching vs. AI inference

**Rationale**: These solve different problems. Pattern matching is deterministic, fast, and free. AI categorization is flexible but costs tokens. Users should explicitly choose their approach.

### 2. **Data Tables Integration - Specialize the Interface**
**Current overlap**: Both read from Data Tables for rules/templates

**Proposed Modification(s)**:
- **RAG_Utils**: Make it the "configuration hub" - owns all Data Tables reads for system configuration
- **Vertex**: Remove Data Tables integration entirely, accept only inline inputs

**Implementation**:
```ruby
# Recipe pattern - RAG_Utils feeds Vertex
1. RAG_Utils: Load categories from Data Tables
2. Transform to inline format
3. Vertex: Accept categories as input array
```

This creates a clear data flow: RAG_Utils → preparation → Vertex → inference

### 3. **Prompt Templates - Single Source of Truth**
**Current overlap**: Both manage templates

**Proposed Modification(s)**:
- **RAG_Utils** owns all prompt template management (`build_rag_prompt`)
- **Vertex** accepts only fully-formed prompts as input

**New Vertex interface**:
```ruby
# Instead of:
categorize_text(text, categories, model)

# Becomes:
send_structured_prompt(prompt, model, response_schema)
```

### 4. **Create Bridge Actions (Optional)**
For backward compatibility, create explicit "bridge" actions:

```ruby
# In Vertex connector
use_rag_classification: {
  title: "Use RAG Utils Classification",
  description: "This action has moved to RAG Utils connector",
  deprecated: true,
  execute: lambda do |connection, input|
    error("Please use 'Evaluate email by rules' action in RAG Utils connector instead. " \
          "This ensures consistent rule processing across your recipes.")
  end
}
```

## **Resulting Architecture**

```
RAG_Utils (Preparation Layer):
├── Document processing (chunking, cleaning)
├── Classification rules (pattern-based)
├── Template management
├── Data Tables integration
├── Embeddings formatting
└── Validation

Vertex (AI Layer):
├── Raw AI inference (send_messages)
├── Specialized AI tasks (translate, summarize)
├── Embeddings generation
├── Vector search
└── Multimodal analysis
```

## **Benefits of This Approach**

1. **Clear mental model**: RAG_Utils = preparation, Vertex = AI
2. **No duplication**: Each action lives in exactly one place
3. **Explicit dependencies**: Recipes show the data flow
4. **Cost clarity**: Users know when they're using paid AI vs. free processing
5. **Testing isolation**: Can test preparation without AI costs

## **Counter-argument to Consider**

The only case for keeping duplication would be **convenience** - users might want everything in one action. But this conflicts with:
- Clarity of purpose
- Maintenance burden  
- Cost transparency
- Testing complexity

*The slight inconvenience of using two actions is outweighed by the architectural clarity and reduced maintenance burden.*

## **Example Recipe Pattern**
```
Trigger: New Email
→ RAG_Utils: Clean email text
→ RAG_Utils: Evaluate email by rules (with Data Table)
→ Decision: Need AI?
  → Yes: Vertex: Send messages (with prepared prompt)
  → No: Apply rule-based action
```
