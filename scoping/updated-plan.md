# Complete Data Tables Mapping for Workato RAG Email Response System

## Primary Data Tables (7 Tables from Document)

### 1. **rag_system_config**
*Purpose: Centralized configuration management*

| Column | Data Type | Constraints | Description |
|--------|-----------|------------|-------------|
| config_key | VARCHAR(100) | PRIMARY KEY | Unique configuration identifier |
| config_value | TEXT | NOT NULL | Configuration value (can be JSON) |
| category | VARCHAR(50) | NOT NULL | Config category (processing, ai_models, etc.) |
| description | TEXT | NULL | Human-readable description |
| updated_at | TIMESTAMP | NOT NULL | Last modification timestamp |

**Key Records:**
- chunk_size, chunk_overlap, embedding_model, gemini_model
- confidence_threshold, max_context_docs, cache_ttl_days

### 2. **email_classification_rules**
*Purpose: Rule-based email filtering (handles 750→150 reduction)*

| Column | Data Type | Constraints | Description |
|--------|-----------|------------|-------------|
| rule_id | VARCHAR(20) | PRIMARY KEY | Unique rule identifier |
| rule_type | VARCHAR(50) | NOT NULL | Type: sender_domain, subject_regex, etc. |
| pattern | VARCHAR(500) | NOT NULL | Pattern to match |
| action | VARCHAR(50) | NOT NULL | Action: archive, delete, need_response |
| priority | INTEGER | NOT NULL | Execution order (1=highest) |
| active | BOOLEAN | NOT NULL DEFAULT TRUE | Is rule active |
| created_at | TIMESTAMP | NOT NULL | Rule creation date |
| hit_count | INTEGER | DEFAULT 0 | Times rule matched |

### 3. **email_processing_queue**
*Purpose: Email processing pipeline management*

| Column | Data Type | Constraints | Description |
|--------|-----------|------------|-------------|
| queue_id | VARCHAR(50) | PRIMARY KEY | Unique queue entry ID |
| message_id | VARCHAR(100) | UNIQUE NOT NULL | Gmail message ID |
| received_at | TIMESTAMP | NOT NULL | Email receipt time |
| sender | VARCHAR(255) | NOT NULL | Sender email address |
| subject | TEXT | NULL | Email subject |
| category | VARCHAR(50) | NULL | Classification result |
| status | VARCHAR(30) | NOT NULL | pending, processing, completed, failed |
| attempts | INTEGER | DEFAULT 0 | Processing attempt count |
| processed_at | TIMESTAMP | NULL | Processing completion time |
| error_message | TEXT | NULL | Error details if failed |
| thread_id | VARCHAR(100) | NULL | Gmail thread ID |
| labels | JSON | NULL | Gmail labels array |

### 4. **response_cache**
*Purpose: Cache frequently asked questions (target 30% hit rate)*

| Column | Data Type | Constraints | Description |
|--------|-----------|------------|-------------|
| cache_id | VARCHAR(50) | PRIMARY KEY | Unique cache entry ID |
| query_hash | VARCHAR(64) | UNIQUE NOT NULL | SHA256 hash of normalized query |
| query_text | TEXT | NOT NULL | Original query text |
| response_text | TEXT | NOT NULL | Cached response |
| confidence | DECIMAL(3,2) | NOT NULL | Response confidence score |
| use_count | INTEGER | DEFAULT 0 | Times response used |
| last_used | TIMESTAMP | NOT NULL | Last access time |
| created_at | TIMESTAMP | NOT NULL | Cache entry creation |
| expires_at | TIMESTAMP | NOT NULL | Cache expiration date |
| source_docs | JSON | NULL | Document IDs used |

### 5. **rag_document_registry**
*Purpose: Track all documents in the knowledge base*

| Column | Data Type | Constraints | Description |
|--------|-----------|------------|-------------|
| document_id | VARCHAR(50) | PRIMARY KEY | Unique document ID |
| source_path | VARCHAR(500) | NOT NULL | Google Drive path |
| storage_path | VARCHAR(500) | NOT NULL | GCS storage path |
| file_hash | VARCHAR(64) | NOT NULL | SHA256 file hash |
| chunk_count | INTEGER | DEFAULT 0 | Number of chunks created |
| embedding_status | VARCHAR(30) | NOT NULL | pending, processing, indexed, failed |
| last_processed | TIMESTAMP | NULL | Last processing timestamp |
| file_size | BIGINT | NULL | File size in bytes |
| mime_type | VARCHAR(100) | NULL | Document MIME type |
| metadata | JSON | NULL | Additional metadata |

### 6. **rag_email_responses**
*Purpose: Track all AI-generated responses*

| Column | Data Type | Constraints | Description |
|--------|-----------|------------|-------------|
| response_id | VARCHAR(50) | PRIMARY KEY | Unique response ID |
| email_message_id | VARCHAR(100) | NOT NULL | Gmail message ID |
| sender | VARCHAR(255) | NOT NULL | Sender email |
| query | TEXT | NOT NULL | Extracted query |
| confidence | DECIMAL(3,2) | NOT NULL | Response confidence |
| response_sent | BOOLEAN | NOT NULL | Was response sent |
| tokens_used | INTEGER | NULL | Total tokens consumed |
| cache_hit | BOOLEAN | NOT NULL | Was cache used |
| response_time_ms | INTEGER | NULL | Response generation time |
| model_used | VARCHAR(50) | NULL | Which AI model |
| created_at | TIMESTAMP | NOT NULL | Response timestamp |

### 7. **monitoring_dashboard**
*Purpose: Real-time metrics and alerting*

| Column | Data Type | Constraints | Description |
|--------|-----------|------------|-------------|
| metric_name | VARCHAR(100) | NOT NULL | Metric identifier |
| metric_value | DECIMAL(10,2) | NOT NULL | Numeric value |
| timestamp | TIMESTAMP | NOT NULL | Measurement time |
| category | VARCHAR(50) | NOT NULL | volume, performance, efficiency, cost |
| alert_triggered | BOOLEAN | DEFAULT FALSE | Alert sent |
| details | JSON | NULL | Additional context |

**Composite Primary Key**: (metric_name, timestamp)

## Additional Supporting Tables (Recommended)

### 8. **document_chunks**
*Purpose: Store individual document chunks*

| Column | Data Type | Constraints | Description |
|--------|-----------|------------|-------------|
| chunk_id | VARCHAR(50) | PRIMARY KEY | Unique chunk ID |
| document_id | VARCHAR(50) | FOREIGN KEY | Parent document |
| chunk_index | INTEGER | NOT NULL | Position in document |
| chunk_text | TEXT | NOT NULL | Chunk content |
| token_count | INTEGER | NOT NULL | Token count |
| embedding_vector | BLOB | NULL | Vector embedding |
| created_at | TIMESTAMP | NOT NULL | Creation time |

### 9. **email_templates**
*Purpose: Response templates for common queries*

| Column | Data Type | Constraints | Description |
|--------|-----------|------------|-------------|
| template_id | VARCHAR(50) | PRIMARY KEY | Unique template ID |
| template_name | VARCHAR(100) | NOT NULL | Template name |
| template_text | TEXT | NOT NULL | Template content |
| placeholders | JSON | NULL | Required variables |
| use_count | INTEGER | DEFAULT 0 | Usage counter |
| active | BOOLEAN | DEFAULT TRUE | Is template active |

### 10. **audit_log**
*Purpose: Complete system audit trail*

| Column | Data Type | Constraints | Description |
|--------|-----------|------------|-------------|
| log_id | VARCHAR(50) | PRIMARY KEY | Unique log ID |
| action_type | VARCHAR(50) | NOT NULL | Action performed |
| entity_type | VARCHAR(50) | NOT NULL | Entity affected |
| entity_id | VARCHAR(50) | NULL | Entity identifier |
| user_id | VARCHAR(100) | NULL | User/service account |
| timestamp | TIMESTAMP | NOT NULL | Action time |
| details | JSON | NULL | Action details |

## Table Relationships

```sql
-- Primary Foreign Key Relationships
document_chunks.document_id → rag_document_registry.document_id
rag_email_responses.email_message_id → email_processing_queue.message_id
response_cache.source_docs (JSON array) → rag_document_registry.document_id

-- Logical Relationships (via application logic)
email_classification_rules → email_processing_queue (applies rules)
rag_system_config → All tables (configuration parameters)
monitoring_dashboard → All tables (aggregates metrics)
```

## Recommended Indexes

```sql
-- Performance-critical indexes
CREATE INDEX idx_queue_status ON email_processing_queue(status, received_at);
CREATE INDEX idx_queue_category ON email_processing_queue(category);
CREATE INDEX idx_cache_hash ON response_cache(query_hash);
CREATE INDEX idx_cache_expiry ON response_cache(expires_at);
CREATE INDEX idx_docs_status ON rag_document_registry(embedding_status);
CREATE INDEX idx_chunks_doc ON document_chunks(document_id, chunk_index);
CREATE INDEX idx_responses_time ON rag_email_responses(created_at DESC);
CREATE INDEX idx_monitor_metric ON monitoring_dashboard(metric_name, timestamp DESC);
CREATE INDEX idx_rules_priority ON email_classification_rules(active, priority);
```

## Data Retention Policies

| Table | Retention Period | Archive Strategy |
|-------|-----------------|------------------|
| email_processing_queue | 30 days | Archive to cold storage |
| rag_email_responses | 90 days | Aggregate then archive |
| response_cache | 30 days (configurable) | Auto-expire |
| monitoring_dashboard | 7 days detailed, 90 days aggregated | Roll up hourly → daily |
| audit_log | 1 year | Compress and archive |
| document_chunks | While parent document active | Delete with parent |

## Workato Lookup Table Configuration

For Workato implementation, configure these as lookup tables with:

1. **Primary Keys**: Set as specified above
2. **Search Fields**: 
   - email_processing_queue: message_id, status
   - response_cache: query_hash
   - rag_document_registry: document_id, source_path
3. **Update Frequency**:
   - Real-time: email_processing_queue, rag_email_responses
   - Cached (5 min): response_cache, monitoring_dashboard
   - On-demand: rag_system_config, email_classification_rules

## Data Volume Estimates

| Table | Daily Records | Total Size (30 days) |
|-------|--------------|---------------------|
| email_processing_queue | 750 | ~22,500 records |
| rag_email_responses | 100 | ~3,000 records |
| response_cache | 20 (new) | ~600 active records |
| monitoring_dashboard | 1,440 (1/min) | ~43,200 records |
| document_chunks | Variable | ~5,000-10,000 chunks |
