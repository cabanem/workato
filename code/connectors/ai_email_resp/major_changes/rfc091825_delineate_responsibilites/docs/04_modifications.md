# Connector Modifications

## **RAG_Utils Connector Modifications**

### **Action 1: Add Contract Validation Infrastructure**
```ruby
# In the methods section, after line ~1500 (after existing helper methods)
# ADD this new method:

validate_contract: lambda do |_connection, data, contract_type|
  contracts = {
    'cleaned_text' => {
      required: ['text', 'metadata'],
      metadata_required: ['original_length', 'cleaned_length', 'processing_applied', 'source_type']
    },
    'embedding_request' => {
      required: ['batch_id', 'texts'],
      texts_required: ['id', 'content', 'metadata']
    },
    'classification_request' => {
      required: ['text', 'classification_mode', 'categories']
    },
    'prompt_request' => {
      required: ['prompt_type', 'formatted_prompt']
    }
  }
  
  contract = contracts[contract_type]
  error("Unknown contract type: #{contract_type}") unless contract
  
  # Check top-level required fields
  missing = contract[:required].select { |field| data[field].nil? || data[field].to_s.empty? }
  error("Contract violation (#{contract_type}): Missing fields #{missing.join(', ')}") if missing.any?
  
  # Check nested requirements
  if contract[:metadata_required] && data['metadata']
    meta_missing = contract[:metadata_required].select { |field| data['metadata'][field].nil? }
    error("Contract violation: metadata missing #{meta_missing.join(', ')}") if meta_missing.any?
  end
  
  data
end,
```

### **Action 2: Rename evaluate_email_by_rules**
```ruby
# FIND this action (around line 871):
evaluate_email_by_rules: {

# REPLACE the entire action name and title with:
classify_by_pattern: {
  title: 'Classify by pattern matching',
  subtitle: 'Pattern-based classification without AI',
  description: 'Evaluate text against pattern rules from standard library or Data Tables',
  
  # KEEP all existing help, config_fields, input_fields, output_fields, execute
  # Just change the action key and title/subtitle/description
```

### **Action 3: Create New prepare_for_ai Action**
```ruby
# ADD this new action after classify_by_pattern (around line 1050):

prepare_for_ai: {
  title: 'Prepare text for AI processing',
  subtitle: 'Clean and format text for Vertex AI',
  description: 'Standardizes text preparation for AI tasks with contract validation',
  
  input_fields: lambda do
    [
      { name: 'text', type: 'string', optional: false, control_type: 'text-area' },
      { name: 'source_type', type: 'string', optional: false,
        control_type: 'select',
        pick_list: [['Email', 'email'], ['Document', 'document'], ['Chat', 'chat'], ['General', 'general']],
        default: 'general' },
      { name: 'task_type', type: 'string', optional: false,
        control_type: 'select', 
        pick_list: [['Classification', 'classification'], ['Generation', 'generation'], 
                   ['Analysis', 'analysis'], ['Embedding', 'embedding']],
        default: 'generation' },
      { name: 'options', type: 'object', optional: true,
        properties: [
          { name: 'remove_pii', type: 'boolean', control_type: 'checkbox', default: false },
          { name: 'max_length', type: 'integer', default: 32000 }
        ]
      }
    ]
  end,
  
  output_fields: lambda do
    [
      { name: 'text', type: 'string' },
      { name: 'metadata', type: 'object', properties: [
        { name: 'original_length', type: 'integer' },
        { name: 'cleaned_length', type: 'integer' },
        { name: 'processing_applied', type: 'array', of: 'string' },
        { name: 'source_type', type: 'string' }
      ]},
      { name: 'extracted_sections', type: 'object' }
    ]
  end,
  
  execute: lambda do |connection, input|
    # Process based on source type
    processed = case input['source_type']
    when 'email'
      call(:process_email_text, {
        'email_body' => input['text'],
        'remove_signatures' => true,
        'remove_quotes' => true,
        'normalize_whitespace' => true
      })
    else
      { 'cleaned_text' => input['text'].to_s.strip }
    end
    
    # Build contract-compliant output
    output = {
      'text' => processed['cleaned_text'],
      'metadata' => {
        'original_length' => input['text'].to_s.length,
        'cleaned_length' => processed['cleaned_text'].length,
        'processing_applied' => ['normalize_whitespace'],
        'source_type' => input['source_type']
      }
    }
    
    # Add source-specific processing
    if input['source_type'] == 'email'
      output['metadata']['processing_applied'] += ['remove_signatures', 'remove_quotes']
      output['extracted_sections'] = {
        'query' => processed['extracted_query']
      } if processed['extracted_query']
    end
    
    # Validate contract
    call(:validate_contract, connection, output, 'cleaned_text')
  end
},
```

### **Action 4: Update format_embeddings_batch to prepare_embedding_batch**
```ruby
# FIND this action (around line 245):
format_embeddings_batch: {

# REPLACE the entire action with:
prepare_embedding_batch: {
  title: 'Prepare embeddings batch',
  subtitle: 'Format texts for batch embedding generation',
  description: 'Prepare texts with metadata for Vertex AI embedding generation',
  
  input_fields: lambda do
    [
      { name: 'texts', type: 'array', of: 'object', optional: false,
        properties: [
          { name: 'id', type: 'string', optional: false },
          { name: 'content', type: 'string', optional: false },
          { name: 'title', type: 'string' },
          { name: 'metadata', type: 'object' }
        ]
      },
      { name: 'task_type', type: 'string', optional: true,
        control_type: 'select',
        pick_list: [['Document', 'RETRIEVAL_DOCUMENT'], ['Query', 'RETRIEVAL_QUERY'],
                    ['Similarity', 'SEMANTIC_SIMILARITY']],
        default: 'RETRIEVAL_DOCUMENT' },
      { name: 'batch_size', type: 'integer', optional: true, default: 25 }
    ]
  end,
  
  output_fields: lambda do
    [
      { name: 'batch_id', type: 'string' },
      { name: 'texts', type: 'array', of: 'object' },
      { name: 'task_type', type: 'string' },
      { name: 'title', type: 'string' }
    ]
  end,
  
  execute: lambda do |connection, input|
    batch_id = "batch_#{Time.now.to_i}_#{rand(1000)}"
    
    output = {
      'batch_id' => batch_id,
      'texts' => input['texts'],
      'task_type' => input['task_type'],
      'title' => input['title']
    }
    
    call(:validate_contract, connection, output, 'embedding_request')
  end
},
```

### **Action 5: Add Deprecation Notice to to_vertex_datapoints**
```ruby
# FIND this action (around line 1100):
to_vertex_datapoints: {

# ADD after the title line:
  deprecated: 'This action will be replaced by format_vector_datapoints in v2.0',
  
# In the execute block, ADD at the beginning:
  execute: lambda do |connection, input|
    puts "DEPRECATION WARNING: to_vertex_datapoints will be replaced by format_vector_datapoints in v2.0"
    # ... rest of existing code
```

## **Vertex AI Connector Modifications**

### **Action 6: Remove All Data Tables Integration**
```ruby
# DELETE these methods entirely (around lines 1800-2000):
- ensure_workato_api!
- workato_api_headers  
- workato_api_base
- list_datatables
- list_datatable_columns
- fetch_datatable_rows
- cached_table_rows
- load_categories_from_table

# Also DELETE in connection fields (around line 50):
- workato_api_host field
- workato_api_token field
```

### **Action 7: Create New ai_classify Action**
```ruby
# ADD this new action after categorize_text (around line 700):

ai_classify: {
  title: 'AI classify text',
  subtitle: 'Pure AI classification without pattern rules',
  description: 'Classify prepared text using AI inference only',
  
  input_fields: lambda do |object_definitions|
    [
      { name: 'text', type: 'string', optional: false, control_type: 'text-area',
        hint: 'Pre-processed text from RAG_Utils' },
      { name: 'categories', type: 'array', of: 'object', optional: false,
        properties: [
          { name: 'key', type: 'string', optional: false },
          { name: 'description', type: 'string' }
        ]
      },
      { name: 'model', optional: false, control_type: 'select',
        pick_list: :available_text_models },
      { name: 'options', type: 'object', optional: true,
        properties: [
          { name: 'return_confidence', type: 'boolean', default: true },
          { name: 'return_alternatives', type: 'integer', default: 0 },
          { name: 'temperature', type: 'number', default: 0 }
        ]
      }
    ].concat(object_definitions['config_schema'].only('safetySettings'))
  end,
  
  output_fields: lambda do
    [
      { name: 'selected_category', type: 'string' },
      { name: 'confidence', type: 'number' },
      { name: 'alternatives', type: 'array', of: 'object',
        properties: [
          { name: 'category', type: 'string' },
          { name: 'confidence', type: 'number' }
        ]
      },
      { name: 'usage', type: 'object' }
    ]
  end,
  
  execute: lambda do |connection, input|
    categories_text = input['categories'].map { |c| 
      "#{c['key']}#{c['description'] ? ': ' + c['description'] : ''}" 
    }.join("\n")
    
    instruction = 'You are a classification assistant. Classify the text into exactly one category.'
    user_prompt = "Categories:\n```#{categories_text}```\n" \
                 "Text: ```#{input['text']}```\n" \
                 "Respond with JSON: {\"category\": \"selected_key\", \"confidence\": 0.0-1.0}"
    
    payload = call('build_base_payload', instruction, user_prompt, input['safetySettings'])
    
    url = "projects/#{connection['project']}/locations/#{connection['region']}" \
          "/#{input['model']}:generateContent"
    
    response = post(url, payload).
      after_error_response(/.*/) do |code, body, _header, message|
        call('handle_vertex_error', connection, code, body, message)
      end
    
    result = call('extract_json', response)
    
    {
      'selected_category' => result['category'],
      'confidence' => result['confidence'].to_f,
      'alternatives' => [],
      'usage' => response['usageMetadata']
    }
  end
},
```

### **Action 8: Add Deprecation to categorize_text**
```ruby
# FIND categorize_text action (around line 600):
categorize_text: {

# ADD after the title:
  deprecated: true,
  title: 'Categorize text (DEPRECATED)',
  subtitle: 'Will be removed in v2.0 - Use ai_classify or RAG_Utils::classify_by_pattern',
  
# In execute block, ADD at beginning:
  execute: lambda do |connection, input, _eis, _eos|
    puts "DEPRECATION WARNING: categorize_text is deprecated. "\
         "Use RAG_Utils::classify_by_pattern for rules or ai_classify for AI classification"
    # ... rest of existing code
```

### **Action 9: Update generate_embedding for Batch Support**
```ruby
# FIND generate_embedding action (around line 900):
# REPLACE the entire action with:

generate_embeddings: {  # Note plural
  title: 'Generate embeddings',
  subtitle: 'Generate embeddings for single or batch texts',
  description: 'Process prepared embedding requests from RAG_Utils',
  
  input_fields: lambda do
    [
      { name: 'batch_id', type: 'string', optional: false },
      { name: 'texts', type: 'array', of: 'object', optional: false,
        properties: [
          { name: 'id', type: 'string' },
          { name: 'content', type: 'string' },
          { name: 'metadata', type: 'object' }
        ]
      },
      { name: 'task_type', type: 'string', optional: true },
      { name: 'model', optional: false, control_type: 'select',
        pick_list: :available_embedding_models }
    ]
  end,
  
  output_fields: lambda do
    [
      { name: 'batch_id', type: 'string' },
      { name: 'embeddings', type: 'array', of: 'object',
        properties: [
          { name: 'id', type: 'string' },
          { name: 'vector', type: 'array', of: 'number' },
          { name: 'dimensions', type: 'integer' }
        ]
      },
      { name: 'model_used', type: 'string' },
      { name: 'usage', type: 'object' }
    ]
  end,
  
  execute: lambda do |connection, input|
    embeddings = []
    total_tokens = 0
    
    input['texts'].each do |text_obj|
      payload = {
        'instances' => [{
          'task_type' => input['task_type'],
          'content' => text_obj['content']
        }]
      }
      
      url = "projects/#{connection['project']}/locations/#{connection['region']}" \
            "/#{input['model']}:predict"
      
      response = post(url, payload).
        after_error_response(/.*/) do |code, body, _header, message|
          call('handle_vertex_error', connection, code, body, message)
        end
      
      vector = call('extract_embedding_response', response)['embedding'].map { |e| e['value'] }
      
      embeddings << {
        'id' => text_obj['id'],
        'vector' => vector,
        'dimensions' => vector.length
      }
      
      total_tokens += text_obj['content'].to_s.length / 4
    end
    
    {
      'batch_id' => input['batch_id'],
      'embeddings' => embeddings,
      'model_used' => input['model'].split('/').last,
      'usage' => { 'total_tokens' => total_tokens }
    }
  end
},
```

### **Action 10: Clean Up Pick Lists**
```ruby
# FIND pick_lists section (around line 2500):
# DELETE these pick lists entirely:
- workato_datatables
- workato_datatable_columns

# They reference deleted methods and are no longer needed
```

## **Verification Checklist**

After completing all actions:

□ RAG_Utils has `validate_contract` method  
□ RAG_Utils has `classify_by_pattern` (renamed from evaluate_email_by_rules)  
□ RAG_Utils has new `prepare_for_ai` action  
□ RAG_Utils has `prepare_embedding_batch` (renamed from format_embeddings_batch)  
□ Vertex has no Data Tables methods  
□ Vertex has new `ai_classify` action  
□ Vertex has deprecated `categorize_text`  
□ Vertex has `generate_embeddings` with batch support  
□ Both connectors compile without errors  
□ Test recipe runs successfully
