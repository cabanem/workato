# Database Schema

| table_name | column_name | type | constraints | purpose | example |
|------------|-------------|------|-------------|---------|---------|
| **rag_system_config** | config_key | VARCHAR(100) | PRIMARY KEY | Unique configuration identifier | "chunk_size" |
| rag_system_config | config_value | TEXT | NOT NULL | Configuration value (can be JSON) | "1000" |
| rag_system_config | category | VARCHAR(50) | NOT NULL | Config category for grouping | "processing" |
| rag_system_config | description | TEXT | NULL | Human-readable description | "Maximum tokens per chunk" |
| rag_system_config | updated_at | TIMESTAMP | NOT NULL DEFAULT CURRENT_TIMESTAMP | Last modification timestamp | "2024-01-15 10:30:00" |
| **email_classification_rules** | rule_id | VARCHAR(20) | PRIMARY KEY | Unique rule identifier | "rule_001" |
| email_classification_rules | rule_type | VARCHAR(50) | NOT NULL | Type of pattern matching | "sender_domain" |
| email_classification_rules | pattern | VARCHAR(500) | NOT NULL | Pattern to match against | "*@noreply.*" |
| email_classification_rules | action | VARCHAR(50) | NOT NULL | Action when rule matches | "archive" |
| email_classification_rules | priority | INTEGER | NOT NULL | Execution order (1=highest) | 1 |
| email_classification_rules | active | BOOLEAN | NOT NULL DEFAULT TRUE | Is rule currently active | true |
| email_classification_rules | created_at | TIMESTAMP | NOT NULL DEFAULT CURRENT_TIMESTAMP | Rule creation date | "2024-01-01 09:00:00" |
| email_classification_rules | hit_count | INTEGER | DEFAULT 0 | Times rule has matched | 1523 |
| email_classification_rules | last_hit | TIMESTAMP | NULL | Last time rule matched | "2024-01-15 14:22:00" |
| **email_processing_queue** | queue_id | VARCHAR(50) | PRIMARY KEY | Unique queue entry ID | "eq_20240115_001" |
| email_processing_queue | message_id | VARCHAR(100) | UNIQUE NOT NULL | Gmail message identifier | "msg_abc123xyz" |
| email_processing_queue | thread_id | VARCHAR(100) | NULL | Gmail thread identifier | "thread_789def" |
| email_processing_queue | received_at | TIMESTAMP | NOT NULL | Email receipt time | "2024-01-15 10:15:00" |
| email_processing_queue | sender | VARCHAR(255) | NOT NULL | Sender email address | "customer@example.com" |
| email_processing_queue | subject | TEXT | NULL | Email subject line | "Question about return policy" |
| email_processing_queue | category | VARCHAR(50) | NULL | Classification result | "needs_response" |
| email_processing_queue | status | VARCHAR(30) | NOT NULL | Processing status | "pending" |
| email_processing_queue | attempts | INTEGER | DEFAULT 0 | Processing attempt count | 0 |
| email_processing_queue | processed_at | TIMESTAMP | NULL | Processing completion time | "2024-01-15 10:15:30" |
| email_processing_queue | response_time_ms | INTEGER | NULL | Time to process in milliseconds | 12500 |
| email_processing_queue | error_message | TEXT | NULL | Error details if failed | NULL |
| email_processing_queue | labels | JSON | NULL | Gmail labels array | '["INBOX", "UNREAD"]' |
| **rag_processing_queue** | job_id | VARCHAR(50) | PRIMARY KEY | Unique job identifier | "job_20240115_001" |
| rag_processing_queue | job_type | VARCHAR(50) | NOT NULL | Type of processing job | "chunk_document" |
| rag_processing_queue | document_id | VARCHAR(50) | NULL | Reference to document registry | "doc_001" |
| rag_processing_queue | source_path | VARCHAR(500) | NULL | Source file location | "/drive/policies/return.pdf" |
| rag_processing_queue | priority | INTEGER | DEFAULT 5 | Job priority (1-10 scale) | 5 |
| rag_processing_queue | status | VARCHAR(30) | NOT NULL | Job status | "processing" |
| rag_processing_queue | attempts | INTEGER | DEFAULT 0 | Retry attempt count | 1 |
| rag_processing_queue | max_attempts | INTEGER | DEFAULT 3 | Maximum retry attempts | 3 |
| rag_processing_queue | created_at | TIMESTAMP | NOT NULL | Job creation time | "2024-01-15 09:00:00" |
| rag_processing_queue | started_at | TIMESTAMP | NULL | Processing start time | "2024-01-15 09:01:00" |
| rag_processing_queue | completed_at | TIMESTAMP | NULL | Processing completion time | "2024-01-15 09:05:00" |
| rag_processing_queue | next_retry_at | TIMESTAMP | NULL | Scheduled retry time | NULL |
| rag_processing_queue | total_items | INTEGER | NULL | Total items to process | 25 |
| rag_processing_queue | processed_items | INTEGER | DEFAULT 0 | Items completed so far | 15 |
| rag_processing_queue | progress_percentage | DECIMAL(5,2) | DEFAULT 0 | Completion percentage | 60.00 |
| rag_processing_queue | result_summary | JSON | NULL | Success details | '{"chunks_created": 25}' |
| rag_processing_queue | error_message | TEXT | NULL | Error description | NULL |
| rag_processing_queue | error_details | JSON | NULL | Detailed error information | NULL |
| rag_processing_queue | tokens_consumed | INTEGER | DEFAULT 0 | API tokens used | 15000 |
| rag_processing_queue | api_calls_made | INTEGER | DEFAULT 0 | Number of API calls | 10 |
| rag_processing_queue | processing_time_seconds | INTEGER | NULL | Total processing time | 240 |
| rag_processing_queue | triggered_by | VARCHAR(100) | NULL | What triggered the job | "drive_change" |
| rag_processing_queue | recipe_name | VARCHAR(100) | NULL | Workato recipe name | "Document_Monitor" |
| rag_processing_queue | correlation_id | VARCHAR(50) | NULL | Links related jobs | "corr_batch_001" |
| **response_cache** | cache_id | VARCHAR(50) | PRIMARY KEY | Unique cache entry ID | "cache_001" |
| response_cache | query_hash | VARCHAR(64) | UNIQUE NOT NULL | SHA256 hash of query | "a3f5b8c9d2e1..." |
| response_cache | query_text | TEXT | NOT NULL | Original query text | "What is your return policy?" |
| response_cache | response_text | TEXT | NOT NULL | Cached response | "Our return policy allows..." |
| response_cache | confidence | DECIMAL(3,2) | NOT NULL | Response confidence score | 0.95 |
| response_cache | use_count | INTEGER | DEFAULT 0 | Times cache entry used | 45 |
| response_cache | last_used | TIMESTAMP | NOT NULL | Last access time | "2024-01-15 14:30:00" |
| response_cache | created_at | TIMESTAMP | NOT NULL | Cache entry creation | "2024-01-01 10:00:00" |
| response_cache | expires_at | TIMESTAMP | NOT NULL | Cache expiration date | "2024-01-31 10:00:00" |
| response_cache | source_docs | JSON | NULL | Document IDs used | '["doc_001", "doc_002"]' |
| response_cache | avg_response_time_ms | INTEGER | NULL | Average response time | 250 |
| response_cache | user_feedback_score | DECIMAL(3,2) | NULL | User rating if provided | 4.5 |
| **rag_document_registry** | document_id | VARCHAR(50) | PRIMARY KEY | Unique document ID | "doc_001" |
| rag_document_registry | source_path | VARCHAR(500) | NOT NULL | Google Drive path | "/policies/return_policy.pdf" |
| rag_document_registry | storage_path | VARCHAR(500) | NOT NULL | GCS storage path | "gs://bucket/docs/doc_001.pdf" |
| rag_document_registry | file_hash | VARCHAR(64) | NOT NULL | SHA256 for change detection | "b4f5c8d9e2a1..." |
| rag_document_registry | chunk_count | INTEGER | DEFAULT 0 | Number of chunks created | 15 |
| rag_document_registry | embedding_status | VARCHAR(30) | NOT NULL | Embedding process status | "indexed" |
| rag_document_registry | last_processed | TIMESTAMP | NULL | Last processing timestamp | "2024-01-15 09:00:00" |
| rag_document_registry | file_size | BIGINT | NULL | File size in bytes | 524288 |
| rag_document_registry | mime_type | VARCHAR(100) | NULL | Document MIME type | "application/pdf" |
| rag_document_registry | version | INTEGER | DEFAULT 1 | Document version number | 2 |
| rag_document_registry | is_active | BOOLEAN | DEFAULT TRUE | Is document active | true |
| rag_document_registry | metadata | JSON | NULL | Custom metadata | '{"author": "Legal Team"}' |
| rag_document_registry | created_at | TIMESTAMP | NOT NULL | Initial creation date | "2024-01-01 08:00:00" |
| rag_document_registry | updated_at | TIMESTAMP | NOT NULL | Last update date | "2024-01-15 09:00:00" |
| **rag_email_responses** | response_id | VARCHAR(50) | PRIMARY KEY | Unique response ID | "resp_001" |
| rag_email_responses | email_message_id | VARCHAR(100) | NOT NULL | Reference to email queue | "msg_abc123xyz" |
| rag_email_responses | sender | VARCHAR(255) | NOT NULL | Original sender email | "customer@example.com" |
| rag_email_responses | query | TEXT | NOT NULL | Extracted user query | "How do I return an item?" |
| rag_email_responses | response_text | TEXT | NULL | Generated response | "To return an item..." |
| rag_email_responses | confidence | DECIMAL(3,2) | NOT NULL | Response confidence score | 0.92 |
| rag_email_responses | response_sent | BOOLEAN | NOT NULL | Was response sent | true |
| rag_email_responses | tokens_used | INTEGER | NULL | Total tokens consumed | 1250 |
| rag_email_responses | cache_hit | BOOLEAN | NOT NULL | Was cache used | false |
| rag_email_responses | response_time_ms | INTEGER | NULL | Response generation time | 8500 |
| rag_email_responses | model_used | VARCHAR(50) | NULL | Which AI model used | "gemini-1.5-pro" |
| rag_email_responses | context_documents | JSON | NULL | Documents used for RAG | '["doc_001", "doc_003"]' |
| rag_email_responses | human_reviewed | BOOLEAN | DEFAULT FALSE | Was human review done | false |
| rag_email_responses | created_at | TIMESTAMP | NOT NULL | Response timestamp | "2024-01-15 10:15:30" |
| **monitoring_dashboard** | metric_name | VARCHAR(100) | NOT NULL (part of composite PK) | Metric identifier | "emails_per_hour" |
| monitoring_dashboard | metric_value | DECIMAL(10,2) | NOT NULL | Numeric value | 45.00 |
| monitoring_dashboard | timestamp | TIMESTAMP | NOT NULL (part of composite PK) | Measurement time | "2024-01-15 10:00:00" |
| monitoring_dashboard | category | VARCHAR(50) | NOT NULL | Metric category | "volume" |
| monitoring_dashboard | alert_triggered | BOOLEAN | DEFAULT FALSE | Was alert sent | false |
| monitoring_dashboard | details | JSON | NULL | Additional context | '{"peak_time": true}' |
| **document_chunks** | chunk_id | VARCHAR(50) | PRIMARY KEY | Unique chunk ID | "chunk_001_001" |
| document_chunks | document_id | VARCHAR(50) | NOT NULL | Parent document reference | "doc_001" |
| document_chunks | chunk_index | INTEGER | NOT NULL | Position in document | 0 |
| document_chunks | chunk_text | TEXT | NOT NULL | Chunk content | "Our return policy states..." |
| document_chunks | token_count | INTEGER | NOT NULL | Number of tokens | 250 |
| document_chunks | embedding_vector | BLOB | NULL | Vector embedding | [binary data] |
| document_chunks | embedding_model | VARCHAR(50) | NULL | Model used for embedding | "text-embedding-004" |
| document_chunks | created_at | TIMESTAMP | NOT NULL | Creation timestamp | "2024-01-15 09:05:00" |
| **email_templates** | template_id | VARCHAR(50) | PRIMARY KEY | Unique template ID | "tmpl_001" |
| email_templates | template_name | VARCHAR(100) | NOT NULL | Template name | "standard_greeting" |
| email_templates | template_text | TEXT | NOT NULL | Template content | "Dear {customer_name},\n\n{body}\n\nBest regards" |
| email_templates | placeholders | JSON | NULL | Required variables | '["customer_name", "body"]' |
| email_templates | category | VARCHAR(50) | NULL | Template category | "customer_service" |
| email_templates | use_count | INTEGER | DEFAULT 0 | Usage counter | 523 |
| email_templates | active | BOOLEAN | DEFAULT TRUE | Is template active | true |
| email_templates | created_at | TIMESTAMP | NOT NULL | Creation date | "2024-01-01 08:00:00" |
| **audit_log** | log_id | VARCHAR(50) | PRIMARY KEY | Unique log ID | "log_20240115_001" |
| audit_log | action_type | VARCHAR(50) | NOT NULL | Action performed | "email_sent" |
| audit_log | entity_type | VARCHAR(50) | NOT NULL | Entity affected | "email_response" |
| audit_log | entity_id | VARCHAR(50) | NULL | Entity identifier | "resp_001" |
| audit_log | user_id | VARCHAR(100) | NULL | User or service account | "workato-rag-operations" |
| audit_log | timestamp | TIMESTAMP | NOT NULL | Action time | "2024-01-15 10:15:45" |
| audit_log | details | JSON | NULL | Action details | '{"status": "success"}' |
| audit_log | ip_address | VARCHAR(45) | NULL | Source IP address | "192.168.1.100" |
| audit_log | recipe_name | VARCHAR(100) | NULL | Workato recipe name | "Response_Sender" |
| **error_recovery** | error_id | VARCHAR(50) | PRIMARY KEY | Unique error ID | "err_20240115_001" |
| error_recovery | source_table | VARCHAR(50) | NOT NULL | Table where error occurred | "email_processing_queue" |
| error_recovery | source_id | VARCHAR(50) | NOT NULL | Record that failed | "eq_20240115_001" |
| error_recovery | error_type | VARCHAR(100) | NOT NULL | Type of error | "api_timeout" |
| error_recovery | error_message | TEXT | NOT NULL | Error description | "Vertex AI timeout after 30s" |
| error_recovery | stack_trace | TEXT | NULL | Full error stack trace | "[detailed stack trace]" |
| error_recovery | recovery_status | VARCHAR(30) | NULL | Recovery attempt status | "retrying" |
| error_recovery | retry_count | INTEGER | DEFAULT 0 | Number of retry attempts | 2 |
| error_recovery | occurred_at | TIMESTAMP | NOT NULL | When error occurred | "2024-01-15 10:30:00" |
| error_recovery | resolved_at | TIMESTAMP | NULL | When error was resolved | "2024-01-15 10:35:00" |
| error_recovery | resolution_notes | TEXT | NULL | How error was resolved | "Retried successfully after 5 min" |

## Summary Statistics
- **Total Tables:** 12
- **Total Columns:** 155
- **Primary Keys:** 12 (one per table, composite for monitoring_dashboard)
- **Foreign Key Relationships:** 5 explicit, multiple logical
- **JSON Columns:** 16 (for flexible metadata storage)
- **Timestamp Columns:** 31 (for comprehensive time tracking)