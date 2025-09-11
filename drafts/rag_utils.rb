{
  title: "RAG Utilities",
  description: "Custom utility functions for RAG email response system",
  version: "1.0",
  
  # ==========================================
  # CONNECTION CONFIGURATION
  # ==========================================
  connection: {
    fields: [
      {
        name: "environment",
        label: "Environment",
        hint: "Select the environment for the connector",
        optional: false,
        control_type: "select",
        pick_list: "environments"
      },
      {
        name: "chunk_size_default",
        label: "Default Chunk Size",
        hint: "Default token size for text chunks",
        optional: true,
        default: "1000",
        control_type: "number"
      },
      {
        name: "chunk_overlap_default",
        label: "Default Chunk Overlap",
        hint: "Default token overlap between chunks",
        optional: true,
        default: "100",
        control_type: "number"
      },
      {
        name: "similarity_threshold",
        label: "Similarity Threshold",
        hint: "Minimum similarity score (0-1)",
        optional: true,
        default: "0.7",
        control_type: "number"
      }
    ],
    
    authorization: {
      type: "custom_auth",
      
      apply: lambda do |connection|
        headers("X-Environment": connection["environment"])
      end
    }
  },
  
  # ==========================================
  # CONNECTION TEST
  # ==========================================
  test: lambda do |connection|
    {
      environment: connection["environment"],
      chunk_size: connection["chunk_size_default"],
      status: "connected"
    }
  end,
  
  # ==========================================
  # ACTIONS
  # ==========================================
  actions: {
    
    # ------------------------------------------
    # 1. SMART CHUNK TEXT
    # ------------------------------------------
    smart_chunk_text: {
      title: "Smart Chunk Text",
      subtitle: "Intelligently chunk text preserving context",
      description: "Splits text into chunks with smart boundaries and overlap",
      
      input_fields: lambda do
        [
          {
            name: "text",
            label: "Input Text",
            type: "string",
            optional: false,
            control_type: "text-area"
          },
          {
            name: "chunk_size",
            label: "Chunk Size (tokens)",
            type: "integer",
            optional: true,
            default: 1000,
            hint: "Maximum tokens per chunk"
          },
          {
            name: "chunk_overlap",
            label: "Chunk Overlap (tokens)",
            type: "integer",
            optional: true,
            default: 100,
            hint: "Token overlap between chunks"
          },
          {
            name: "preserve_sentences",
            label: "Preserve Sentences",
            type: "boolean",
            optional: true,
            default: true,
            hint: "Don't break mid-sentence"
          },
          {
            name: "preserve_paragraphs",
            label: "Preserve Paragraphs",
            type: "boolean",
            optional: true,
            default: false,
            hint: "Try to keep paragraphs intact"
          }
        ]
      end,
      
      output_fields: lambda do
        [
          {
            name: "chunks",
            type: "array",
            of: "object",
            properties: [
              { name: "chunk_id", type: "string" },
              { name: "chunk_index", type: "integer" },
              { name: "text", type: "string" },
              { name: "token_count", type: "integer" },
              { name: "start_char", type: "integer" },
              { name: "end_char", type: "integer" },
              { name: "metadata", type: "object" }
            ]
          },
          {
            name: "total_chunks",
            type: "integer"
          },
          {
            name: "total_tokens",
            type: "integer"
          }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:chunk_text_with_overlap, input)
      end
    },
    
    # ------------------------------------------
    # 2. CLEAN EMAIL TEXT
    # ------------------------------------------
    clean_email_text: {
      title: "Clean Email Text",
      subtitle: "Preprocess email content for RAG",
      description: "Removes signatures, quotes, and normalizes email text",
      
      input_fields: lambda do
        [
          {
            name: "email_body",
            label: "Email Body",
            type: "string",
            optional: false,
            control_type: "text-area"
          },
          {
            name: "remove_signatures",
            label: "Remove Signatures",
            type: "boolean",
            optional: true,
            default: true
          },
          {
            name: "remove_quotes",
            label: "Remove Quoted Text",
            type: "boolean",
            optional: true,
            default: true
          },
          {
            name: "remove_disclaimers",
            label: "Remove Disclaimers",
            type: "boolean",
            optional: true,
            default: true
          },
          {
            name: "normalize_whitespace",
            label: "Normalize Whitespace",
            type: "boolean",
            optional: true,
            default: true
          },
          {
            name: "extract_urls",
            label: "Extract URLs",
            type: "boolean",
            optional: true,
            default: false
          }
        ]
      end,
      
      output_fields: lambda do
        [
          { name: "cleaned_text", type: "string" },
          { name: "extracted_query", type: "string" },
          { name: "removed_sections", type: "array", of: "string" },
          { name: "extracted_urls", type: "array", of: "string" },
          { name: "original_length", type: "integer" },
          { name: "cleaned_length", type: "integer" },
          { name: "reduction_percentage", type: "number" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:process_email_text, input)
      end
    },
    
    # ------------------------------------------
    # 3. CALCULATE SIMILARITY
    # ------------------------------------------
    calculate_similarity: {
      title: "Calculate Vector Similarity",
      subtitle: "Calculate cosine similarity between vectors",
      description: "Computes similarity scores for vector embeddings",
      
      input_fields: lambda do
        [
          {
            name: "vector_a",
            label: "Vector A",
            type: "array",
            of: "number",
            optional: false,
            hint: "First embedding vector"
          },
          {
            name: "vector_b",
            label: "Vector B",
            type: "array",
            of: "number",
            optional: false,
            hint: "Second embedding vector"
          },
          {
            name: "similarity_type",
            label: "Similarity Type",
            type: "string",
            optional: true,
            default: "cosine",
            control_type: "select",
            pick_list: "similarity_types"
          },
          {
            name: "normalize",
            label: "Normalize Vectors",
            type: "boolean",
            optional: true,
            default: true
          }
        ]
      end,
      
      output_fields: lambda do
        [
          { name: "similarity_score", type: "number" },
          { name: "similarity_percentage", type: "number" },
          { name: "is_similar", type: "boolean" },
          { name: "similarity_type", type: "string" },
          { name: "computation_time_ms", type: "integer" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:compute_similarity, input, connection)
      end
    },
    
    # ------------------------------------------
    # 4. FORMAT EMBEDDINGS BATCH
    # ------------------------------------------
    format_embeddings_batch: {
      title: "Format Embeddings for Vertex AI",
      subtitle: "Format embeddings for batch processing",
      description: "Prepares embedding data for Vertex AI Vector Search",
      
      input_fields: lambda do
        [
          {
            name: "embeddings",
            label: "Embeddings Data",
            type: "array",
            of: "object",
            properties: [
              { name: "id", type: "string" },
              { name: "vector", type: "array", of: "number" },
              { name: "metadata", type: "object" }
            ],
            optional: false
          },
          {
            name: "index_endpoint",
            label: "Index Endpoint ID",
            type: "string",
            optional: false
          },
          {
            name: "batch_size",
            label: "Batch Size",
            type: "integer",
            optional: true,
            default: 25,
            hint: "Embeddings per batch"
          },
          {
            name: "format_type",
            label: "Format Type",
            type: "string",
            optional: true,
            default: "json",
            control_type: "select",
            pick_list: "format_types"
          }
        ]
      end,
      
      output_fields: lambda do
        [
          {
            name: "formatted_batches",
            type: "array",
            of: "object",
            properties: [
              { name: "batch_id", type: "string" },
              { name: "batch_number", type: "integer" },
              { name: "datapoints", type: "array" },
              { name: "size", type: "integer" }
            ]
          },
          { name: "total_batches", type: "integer" },
          { name: "total_embeddings", type: "integer" },
          { name: "index_endpoint", type: "string" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:format_for_vertex_ai, input)
      end
    },
    
    # ------------------------------------------
    # 5. BUILD RAG PROMPT
    # ------------------------------------------
    build_rag_prompt: {
      title: "Build RAG Prompt",
      subtitle: "Construct optimized RAG prompt",
      description: "Creates a prompt with context and query for LLM",
      
      input_fields: lambda do
        [
          {
            name: "query",
            label: "User Query",
            type: "string",
            optional: false,
            control_type: "text-area"
          },
          {
            name: "context_documents",
            label: "Context Documents",
            type: "array",
            of: "object",
            properties: [
              { name: "content", type: "string" },
              { name: "relevance_score", type: "number" },
              { name: "source", type: "string" },
              { name: "metadata", type: "object" }
            ],
            optional: false
          },
          {
            name: "prompt_template",
            label: "Prompt Template",
            type: "string",
            optional: true,
            control_type: "select",
            pick_list: "prompt_templates"
          },
          {
            name: "max_context_length",
            label: "Max Context Length",
            type: "integer",
            optional: true,
            default: 3000
          },
          {
            name: "include_metadata",
            label: "Include Metadata",
            type: "boolean",
            optional: true,
            default: false
          },
          {
            name: "system_instructions",
            label: "System Instructions",
            type: "string",
            optional: true,
            control_type: "text-area"
          }
        ]
      end,
      
      output_fields: lambda do
        [
          { name: "formatted_prompt", type: "string" },
          { name: "token_count", type: "integer" },
          { name: "context_used", type: "integer" },
          { name: "truncated", type: "boolean" },
          { name: "prompt_metadata", type: "object" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:construct_rag_prompt, input)
      end
    },
    
    # ------------------------------------------
    # 6. VALIDATE LLM RESPONSE
    # ------------------------------------------
    validate_llm_response: {
      title: "Validate LLM Response",
      subtitle: "Validate and score LLM output",
      description: "Checks response quality and relevance",
      
      input_fields: lambda do
        [
          {
            name: "response_text",
            label: "LLM Response",
            type: "string",
            optional: false,
            control_type: "text-area"
          },
          {
            name: "original_query",
            label: "Original Query",
            type: "string",
            optional: false
          },
          {
            name: "context_provided",
            label: "Context Documents",
            type: "array",
            of: "string",
            optional: true
          },
          {
            name: "validation_rules",
            label: "Validation Rules",
            type: "array",
            of: "object",
            properties: [
              { name: "rule_type", type: "string" },
              { name: "rule_value", type: "string" }
            ],
            optional: true
          },
          {
            name: "min_confidence",
            label: "Minimum Confidence",
            type: "number",
            optional: true,
            default: 0.7
          }
        ]
      end,
      
      output_fields: lambda do
        [
          { name: "is_valid", type: "boolean" },
          { name: "confidence_score", type: "number" },
          { name: "validation_results", type: "object" },
          { name: "issues_found", type: "array", of: "string" },
          { name: "requires_human_review", type: "boolean" },
          { name: "suggested_improvements", type: "array", of: "string" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_response, input, connection)
      end
    },
    
    # ------------------------------------------
    # 7. GENERATE DOCUMENT METADATA
    # ------------------------------------------
    generate_document_metadata: {
      title: "Generate Document Metadata",
      subtitle: "Extract metadata from documents",
      description: "Generates comprehensive metadata for document indexing",
      
      input_fields: lambda do
        [
          {
            name: "document_content",
            label: "Document Content",
            type: "string",
            optional: false,
            control_type: "text-area"
          },
          {
            name: "file_path",
            label: "File Path",
            type: "string",
            optional: false
          },
          {
            name: "file_type",
            label: "File Type",
            type: "string",
            optional: true,
            control_type: "select",
            pick_list: "file_types"
          },
          {
            name: "extract_entities",
            label: "Extract Entities",
            type: "boolean",
            optional: true,
            default: true
          },
          {
            name: "generate_summary",
            label: "Generate Summary",
            type: "boolean",
            optional: true,
            default: true
          }
        ]
      end,
      
      output_fields: lambda do
        [
          { name: "document_id", type: "string" },
          { name: "file_hash", type: "string" },
          { name: "word_count", type: "integer" },
          { name: "character_count", type: "integer" },
          { name: "estimated_tokens", type: "integer" },
          { name: "language", type: "string" },
          { name: "summary", type: "string" },
          { name: "key_topics", type: "array", of: "string" },
          { name: "entities", type: "object" },
          { name: "created_at", type: "timestamp" },
          { name: "processing_time_ms", type: "integer" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:extract_metadata, input)
      end
    },
    
    # ------------------------------------------
    # 8. CHECK DOCUMENT CHANGES
    # ------------------------------------------
    check_document_changes: {
      title: "Check Document Changes",
      subtitle: "Detect changes in documents",
      description: "Compares document versions to detect modifications",
      
      input_fields: lambda do
        [
          {
            name: "current_hash",
            label: "Current Document Hash",
            type: "string",
            optional: false
          },
          {
            name: "current_content",
            label: "Current Content",
            type: "string",
            optional: true,
            control_type: "text-area"
          },
          {
            name: "previous_hash",
            label: "Previous Document Hash",
            type: "string",
            optional: false
          },
          {
            name: "previous_content",
            label: "Previous Content",
            type: "string",
            optional: true,
            control_type: "text-area"
          },
          {
            name: "check_type",
            label: "Check Type",
            type: "string",
            optional: true,
            default: "hash",
            control_type: "select",
            pick_list: "check_types"
          }
        ]
      end,
      
      output_fields: lambda do
        [
          { name: "has_changed", type: "boolean" },
          { name: "change_type", type: "string" },
          { name: "change_percentage", type: "number" },
          { name: "added_content", type: "array", of: "string" },
          { name: "removed_content", type: "array", of: "string" },
          { name: "modified_sections", type: "array", of: "object" },
          { name: "requires_reindexing", type: "boolean" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:detect_changes, input)
      end
    },
    
    # ------------------------------------------
    # 9. CALCULATE METRICS
    # ------------------------------------------
    calculate_metrics: {
      title: "Calculate Performance Metrics",
      subtitle: "Calculate system performance metrics",
      description: "Computes various performance and efficiency metrics",
      
      input_fields: lambda do
        [
          {
            name: "metric_type",
            label: "Metric Type",
            type: "string",
            optional: false,
            control_type: "select",
            pick_list: "metric_types"
          },
          {
            name: "data_points",
            label: "Data Points",
            type: "array",
            of: "object",
            properties: [
              { name: "timestamp", type: "timestamp" },
              { name: "value", type: "number" },
              { name: "metadata", type: "object" }
            ],
            optional: false
          },
          {
            name: "aggregation_period",
            label: "Aggregation Period",
            type: "string",
            optional: true,
            default: "hour",
            control_type: "select",
            pick_list: "time_periods"
          },
          {
            name: "include_percentiles",
            label: "Include Percentiles",
            type: "boolean",
            optional: true,
            default: true
          }
        ]
      end,
      
      output_fields: lambda do
        [
          { name: "average", type: "number" },
          { name: "median", type: "number" },
          { name: "min", type: "number" },
          { name: "max", type: "number" },
          { name: "std_deviation", type: "number" },
          { name: "percentile_95", type: "number" },
          { name: "percentile_99", type: "number" },
          { name: "total_count", type: "integer" },
          { name: "trend", type: "string" },
          { name: "anomalies_detected", type: "array", of: "object" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:compute_metrics, input)
      end
    },
    
    # ------------------------------------------
    # 10. OPTIMIZE BATCH SIZE
    # ------------------------------------------
    optimize_batch_size: {
      title: "Optimize Batch Size",
      subtitle: "Calculate optimal batch size for processing",
      description: "Determines optimal batch size based on performance data",
      
      input_fields: lambda do
        [
          {
            name: "total_items",
            label: "Total Items to Process",
            type: "integer",
            optional: false
          },
          {
            name: "processing_history",
            label: "Processing History",
            type: "array",
            of: "object",
            properties: [
              { name: "batch_size", type: "integer" },
              { name: "processing_time", type: "number" },
              { name: "success_rate", type: "number" },
              { name: "memory_usage", type: "number" }
            ],
            optional: true
          },
          {
            name: "optimization_target",
            label: "Optimization Target",
            type: "string",
            optional: true,
            default: "throughput",
            control_type: "select",
            pick_list: "optimization_targets"
          },
          {
            name: "max_batch_size",
            label: "Maximum Batch Size",
            type: "integer",
            optional: true,
            default: 100
          },
          {
            name: "min_batch_size",
            label: "Minimum Batch Size",
            type: "integer",
            optional: true,
            default: 10
          }
        ]
      end,
      
      output_fields: lambda do
        [
          { name: "optimal_batch_size", type: "integer" },
          { name: "estimated_batches", type: "integer" },
          { name: "estimated_processing_time", type: "number" },
          { name: "throughput_estimate", type: "number" },
          { name: "confidence_score", type: "number" },
          { name: "recommendation_reason", type: "string" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:calculate_optimal_batch, input)
      end
    }
  },
  
  # ==========================================
  # METHODS (Helper Functions)
  # ==========================================
  methods: {
    
    chunk_text_with_overlap: lambda do |input|
      text = input['text'].to_s
      chunk_size = (input['chunk_size'] || 1000).to_i
      overlap    = (input['chunk_overlap'] || 100).to_i
      preserve_sentences  = !!input['preserve_sentences']
      preserve_paragraphs = !!input['preserve_paragraphs']

      overlap = [overlap, [chunk_size - 1, 0].max].min
      chars_per_chunk = [chunk_size, 1].max * 4
      char_overlap    = overlap * 4

      chunks, chunk_index, position = [], 0, 0

      while position < text.length
        tentative_end = [position + chars_per_chunk, text.length].min
        chunk_end = tentative_end
        segment = text[position...tentative_end]

        if preserve_paragraphs && tentative_end < text.length
          if (matches = segment.scan(/\n{2,}/)).any?
            last = matches.last
            idx  = segment.rindex(last)
            chunk_end = position + idx + last.length
          end
        end

        if preserve_sentences && chunk_end == tentative_end && tentative_end < text.length
          if (matches = segment.scan(/[.!?]["')\]]?\s/)).any?
            last = matches.last
            idx  = segment.rindex(last)
            chunk_end = position + idx + last.length
          end
        end

        chunk_end = tentative_end if chunk_end <= position
        chunk_text = text[position...chunk_end]

        chunks << {
          chunk_id:    "chunk_#{chunk_index}",
          chunk_index: chunk_index,
          text:        chunk_text,
          token_count: (chunk_text.length / 4.0).ceil,
          start_char:  position,
          end_char:    chunk_end,
          metadata:    { has_overlap: chunk_index.positive?, is_final: chunk_end >= text.length }
        }

        break if chunk_end >= text.length
        # guaranteed forward movement
        next_position = chunk_end - char_overlap
        position = next_position > position ? next_position : chunk_end # always advance
        chunk_index += 1
      end

      { chunks: chunks,
        total_chunks: chunks.length,
        total_tokens: chunks.sum { |c| c[:token_count] } }
    end,
    
    process_email_text: lambda do |input|
      cleaned = (input['email_body'] || '').dup
      original_length = cleaned.length
      removed_sections = []
      extracted_urls = []

      cleaned.gsub!("\r\n", "\n")

      if input['remove_quotes']
        removed_sections += cleaned.scan(/^\s*>.*$/)
        cleaned.gsub!(/^\s*>.*$/ , '') # line mode, not /m
      end

      if input['remove_signatures']
        lines = cleaned.lines
        sig_idx = lines.rindex { |l| l =~ /^\s*(--\s*$|Best regards,|Regards,|Sincerely,|Thanks,|Sent from my)/i }
        if sig_idx
          removed_sections << lines[sig_idx..-1].join
          cleaned = lines[0...sig_idx].join
        end
      end

      if input['remove_disclaimers']
        lines = cleaned.lines
        disc_idx = lines.rindex { |l| l =~ /(This (e-)?mail|This message).*(confidential|intended only)/i }
        if disc_idx && disc_idx >= lines.length - 25
          removed_sections << lines[disc_idx..-1].join
          cleaned = lines[0...disc_idx].join
        end
      end

      if input['extract_urls']
        extracted_urls = cleaned.scan(%r{https?://[^\s<>"'()]+})
      end

      if input['normalize_whitespace']
        cleaned.gsub!(/[ \t]+/, ' ')
        cleaned.gsub!(/\n{3,}/, "\n\n")
        cleaned.strip!
      end

      extracted_query = cleaned.split(/\n{2,}/).find { |p| p.strip.length.positive? } || cleaned[0, 200].to_s

      {
        cleaned_text: cleaned,
        extracted_query: extracted_query,
        removed_sections: removed_sections,
        extracted_urls: extracted_urls,
        original_length: original_length,
        cleaned_length: cleaned.length,
        reduction_percentage: (original_length.zero? ? 0 : ((1 - cleaned.length.to_f / original_length) * 100)).round(2)
      }
    end,
    
    compute_similarity: lambda do |input, connection|
      start_time = Time.now
      
      vector_a = input["vector_a"]
      vector_b = input["vector_b"]
      threshold = connection["similarity_threshold"].to_f
      
      # Normalize vectors if requested
      if input["normalize"]
        mag_a = Math.sqrt(vector_a.map { |x| x**2 }.sum)
        mag_b = Math.sqrt(vector_b.map { |x| x**2 }.sum)
        vector_a = vector_a.map { |x| x / mag_a } if mag_a > 0
        vector_b = vector_b.map { |x| x / mag_b } if mag_b > 0
      end
      
      # Calculate cosine similarity
      dot_product = vector_a.zip(vector_b).map { |a, b| a * b }.sum
      mag_a = Math.sqrt(vector_a.map { |x| x**2 }.sum)
      mag_b = Math.sqrt(vector_b.map { |x| x**2 }.sum)
      
      similarity = mag_a > 0 && mag_b > 0 ? dot_product / (mag_a * mag_b) : 0
      
      {
        similarity_score: similarity.round(4),
        similarity_percentage: (similarity * 100).round(2),
        is_similar: similarity >= threshold,
        similarity_type: input["similarity_type"] || "cosine",
        computation_time_ms: ((Time.now - start_time) * 1000).round
      }
    end,
    
    format_for_vertex_ai: lambda do |input|
      embeddings = input["embeddings"]
      batch_size = input["batch_size"] || 25
      
      batches = []
      embeddings.each_slice(batch_size).with_index do |batch, index|
        formatted_batch = {
          batch_id: "batch_#{index}",
          batch_number: index,
          datapoints: batch.map do |emb|
            {
              datapoint_id: emb["id"],
              feature_vector: emb["vector"],
              restricts: emb["metadata"] || {}
            }
          end,
          size: batch.length
        }
        batches << formatted_batch
      end
      
      {
        formatted_batches: batches,
        total_batches: batches.length,
        total_embeddings: embeddings.length,
        index_endpoint: input["index_endpoint"]
      }
    end
  },
  
  # ==========================================
  # OBJECT DEFINITIONS (Schemas)
  # ==========================================
  object_definitions: {
    
    chunk_object: {
      fields: lambda do
        [
          { name: "chunk_id", type: "string" },
          { name: "chunk_index", type: "integer" },
          { name: "text", type: "string" },
          { name: "token_count", type: "integer" },
          { name: "start_char", type: "integer" },
          { name: "end_char", type: "integer" },
          { name: "metadata", type: "object" }
        ]
      end
    },
    
    embedding_object: {
      fields: lambda do
        [
          { name: "id", type: "string" },
          { name: "vector", type: "array", of: "number" },
          { name: "metadata", type: "object" }
        ]
      end
    },
    
    metric_datapoint: {
      fields: lambda do
        [
          { name: "timestamp", type: "timestamp" },
          { name: "value", type: "number" },
          { name: "metadata", type: "object" }
        ]
      end
    }
  },
  
  # ==========================================
  # PICK LISTS (Dropdown Options)
  # ==========================================
  pick_lists: {
    
    environments: lambda do
      [
        ["Development", "dev"],
        ["Staging", "staging"],
        ["Production", "prod"]
      ]
    end,
    
    similarity_types: lambda do
      [
        ["Cosine Similarity", "cosine"],
        ["Euclidean Distance", "euclidean"],
        ["Dot Product", "dot_product"]
      ]
    end,
    
    format_types: lambda do
      [
        ["JSON", "json"],
        ["JSONL", "jsonl"],
        ["CSV", "csv"]
      ]
    end,
    
    prompt_templates: lambda do
      [
        ["Standard RAG", "standard"],
        ["Customer Service", "customer_service"],
        ["Technical Support", "technical"],
        ["Sales Inquiry", "sales"],
        ["Custom", "custom"]
      ]
    end,
    
    file_types: lambda do
      [
        ["PDF", "pdf"],
        ["Word Document", "docx"],
        ["Text File", "txt"],
        ["Markdown", "md"],
        ["HTML", "html"]
      ]
    end,
    
    check_types: lambda do
      [
        ["Hash Only", "hash"],
        ["Content Diff", "content"],
        ["Smart Diff", "smart"]
      ]
    end,
    
    metric_types: lambda do
      [
        ["Response Time", "response_time"],
        ["Token Usage", "token_usage"],
        ["Cache Hit Rate", "cache_hit"],
        ["Error Rate", "error_rate"],
        ["Throughput", "throughput"]
      ]
    end,
    
    time_periods: lambda do
      [
        ["Minute", "minute"],
        ["Hour", "hour"],
        ["Day", "day"],
        ["Week", "week"]
      ]
    end,
    
    optimization_targets: lambda do
      [
        ["Throughput", "throughput"],
        ["Latency", "latency"],
        ["Cost", "cost"],
        ["Accuracy", "accuracy"]
      ]
    end
  }
}