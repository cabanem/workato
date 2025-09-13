# Workato Vertex AI Connector

## Original Component and Feature Analysis

### 1. Endpoints and API calls
    Base url pattern ==  `https://{region}-aiplatform.googleapis.com/{version}/`

| Use | Endpoint | Method (appended) |
| :------  | :---- | :--- |
| Gemini model interactions | projects/{project}/locations/{region}/publishers/google/models/{model} | `:generateContent` | 
| Predictions, embeddings | projects/{project}/locations/{region}/publishers/google/models/{model} | `:predict` |
| connection testing | projects/{project}/locations/{region}/datasets | n/a |


### 2. Actions Analysis

#### **send_messages**
- **Purpose:** Converse with Gemini models in Google Vertex AI
- **Endpoint:** `generateContent`
- **Inputs:**
  - Model selection
  - Message type (single_message or chat_transcript)
  - Message content or chat history
  - Optional: tools, tool config, safety settings, generation config, system instruction
- **Outputs:** Candidates array with content, finish reason, safety ratings, usage metadata
- **Processing:** Calls `payload_for_send_message` method to format request, handles response schemas and function declarations

#### **translate_text**
- **Purpose:** Translate text between languages
- **Endpoint:** `generateContent`
- **Inputs:**
  - Model selection
  - Source text (up to 2000 tokens)
  - Target language (required)
  - Source language (optional)
  - Safety settings
- **Outputs:** Translated text with safety ratings and token usage
- **Processing:** Uses `payload_for_translate` to construct system instruction, enforces JSON response format

#### **summarize_text**
- **Purpose:** Generate text summaries with configurable length
- **Endpoint:** `generateContent`
- **Inputs:**
  - Model selection
  - Source text
  - Maximum words (default: 200)
  - Safety settings
- **Outputs:** Summary text with safety ratings and token usage
- **Processing:** Uses `payload_for_summarize` to set system instructions for summarization

#### **parse_text**
- **Purpose:** Extract structured data from unstructured text
- **Endpoint:** `generateContent`
- **Inputs:**
  - Model selection
  - Source text
  - Object schema (user-defined fields to extract)
  - Safety settings
- **Outputs:** Extracted data matching the defined schema, plus safety ratings and usage
- **Processing:** Uses `payload_for_parse` to format schema extraction instructions, returns JSON object

#### **draft_email**
- **Purpose:** Generate email content based on description
- **Endpoint:** `generateContent`
- **Inputs:**
  - Model selection
  - Email description
  - Safety settings
- **Outputs:** Email subject and body, safety ratings, token usage
- **Processing:** Uses `payload_for_email` to create email generation prompt, extracts structured response

#### **categorize_text**
- **Purpose:** Classify text into user-defined categories
- **Endpoint:** `generateContent`
- **Inputs:**
  - Model selection
  - Source text
  - Categories list (with optional rules)
  - Safety settings
- **Outputs:** Best matching category, safety ratings, token usage
- **Processing:** Uses `payload_for_categorize` to format classification instructions

#### **analyze_text**
- **Purpose:** Answer questions about provided text
- **Endpoint:** `generateContent`
- **Inputs:**
  - Model selection
  - Source text
  - Question/instruction
  - Safety settings
- **Outputs:** Analysis answer, safety ratings, token usage
- **Processing:** Uses `payload_for_analyze` to create contextual analysis prompt

#### **analyze_image**
- **Purpose:** Analyze images based on questions
- **Endpoint:** `generateContent`
- **Inputs:**
  - Model selection (image-capable models)
  - Question about the image
  - Image data (base64 encoded)
  - MIME type
  - Safety settings
- **Outputs:** Analysis answer, safety ratings, token usage
- **Processing:** Uses `payload_for_analyze_image` to format multimodal request

#### **generate_embedding**
- **Purpose:** Generate vector embeddings for text
- **Endpoint:** `predict`
- **Inputs:**
  - Model selection (embedding models)
  - Text (max 8192 tokens)
  - Task type (optional: RETRIEVAL_QUERY, RETRIEVAL_DOCUMENT, etc.)
  - Title (for RETRIEVAL_DOCUMENT task)
- **Outputs:** Array of embedding values
- **Processing:** Uses `payload_for_text_embedding` to format prediction request

#### **get_prediction**
- **Purpose:** Get predictions using PaLM 2 text-bison model
- **Endpoint:** `predict` (fixed to text-bison model)
- **Inputs:**
  - Instances array with prompts
  - Parameters (temperature, maxOutputTokens, topK, topP, etc.)
- **Outputs:** Predictions with content, citations, safety attributes, metadata
- **Processing:** Direct API call without additional payload transformation

### 3. Methods (Helper Functions) Analysis

#### **Payload Construction Methods:**
- `payload_for_send_message` - Formats messages for send_messages action, handles single/multi-turn conversations
- `payload_for_translate` - Creates translation-specific system instructions
- `payload_for_summarize` - Sets summarization parameters
- `payload_for_parse` - Formats schema extraction instructions
- `payload_for_email` - Creates email generation prompt
- `payload_for_categorize` - Formats classification instructions with categories
- `payload_for_analyze` - Creates contextual analysis prompt
- `payload_for_analyze_image` - Formats multimodal request with image data
- `payload_for_text_embedding` - Formats embedding generation request

#### **Response Processing Methods:**
- `extract_generic_response` - Extracts answer from API response, handles JSON/text formats
- `extract_generated_email_response` - Parses email subject and body from response
- `extract_parsed_response` - Extracts structured data based on schema
- `extract_embedding_response` - Formats embedding values from prediction response
- `extract_json` - Cleans and parses JSON from model responses

#### **Utility Methods:**
- `get_safety_ratings` - Transforms safety ratings into structured format
- `check_finish_reason` - Validates completion status and throws errors for problematic finishes
- `replace_backticks_with_hash` - Sanitizes text to prevent markdown conflicts
- `make_schema_builder_fields_sticky` - Adds sticky property to schema fields
- `format_parse_sample` - Generates sample output based on schema

#### **Sample Data Methods:**
- `sample_record_output` - Provides sample outputs for different action types
- `safety_ratings_output_sample` - Returns sample safety ratings structure
- `usage_output_sample` - Returns sample token usage structure

### 4. Key Features:
- **Multi-model support:** Gemini Pro, Flash, Vision models, and text-bison
- **Authentication:** OAuth2 and Service Account (JWT) support
- **Safety controls:** Configurable safety thresholds and categories
- **Function calling:** Support for tool declarations and function responses
- **Response formatting:** JSON schema enforcement for structured outputs
- **Error handling:** Comprehensive finish reason checking and error messages
- **Token management:** Usage tracking and limits configuration