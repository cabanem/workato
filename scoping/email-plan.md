# 

## Proof of Concept Scope
### 1. Recipes
1. New email triage and draft
    - Native gmail connector &rarr; apply heuristics &rarr; label &rarr; draft a reply
    - Gmail connector
2. Drive -- GCS sync
    - Drive &rarr; export &rarr; upload to GCS
3. Indexer
4. RAG + draft

**Configuration**
- Use project properties for constant (e.g., label IDs, bucket names, thresholds)
- Lookup table for category routing and/or allow-list

**Upgrade Pathway**

| Objective | Action Required                           |
| :---      | :---------------------------------------- |
| Set `threadId` and RFC-822 headers | Switch Gmail threading/drafts from native Workato connector to custom actions |
| Connect embeddings, translate, and vector search via custom connector | Add a Workato SDK custom connector with JWT service-account auth |
| Monitor for Drive Changes | Add a custom connector to call this endpoint |
| Integrate telemetry | Consider adding autosend policy to BigQuery via Workato native connector |
---
### 2. Connections
- Gmail (OAuth 2.0)
- Google Translate
- Google Drive
- Google Cloud Storage

> **Upgrade Pathway**<br/>
> Add a custom SDK (e.g., "Google SA (JWT)") that mints OAuth tokens using SA keys, calls Vertex AI, Vector Search, Translation, and GCS JSON API with `Authorization: Bearer`

---
### 3. Data and Configuration
- Project properties<br/>
 _Create/manage in Project settings → Project properties_<br/>
    - labels.heuristic, labels.needs_rag, labels.review, labels.autosend_ready, labels.sent
    - gcs.bucket_raw, gcs.bucket_txt
    - policy.autosend_threshold, policy.language_gate

- Lookup tables
    - `category_map` (keyword &rarr; category)
    - `autosend_allowlist` (category &rarr; true/false)

---
## Recipes
### New email triage and draft
<details>
<summary><strong>Trigger(s)</strong></summary>
Gmail &rarr; New email
</details>
<br/>
<details>
<summary><strong>Input(s)</strong></summary>
<ul><li>Label [optional]</li>
<li>Poll interval (min allowed)</li></ul>
</details>
<br/>
<details>
<summary><strong>Outcome(s)</strong></summary>
<ul>
<li> If language != `en` or attachments exist &rarr; label for review </li>
<li> If heuristic matched &rarr; label and skip RAG</li>
<li> Else, label for RAG processing </li>
</ul>
</details>
<br/>

**Step(s)**
1. Language gate
2. Attachment gate
3. Apply heuristics
4. Apply labels
5. Draft a reply
    - Gmail &rarr; Custom action &rarr; `users.messages.get` to fetch headers
    - Build RFC-2822 with Message Template (by Workato)
        ```
        To: {{from_email}}
        Subject: Re: {{subject}}
        In-Reply-To: <{{message_id}}>
        References: {{references}} <{{message_id}}>
        Content-Type: text/plain; charset=UTF-8
        MIME-Version: 1.0

        {{your_draft_text}}
        ```
    - Base64url-encode &rarr; call Gmail &rarr; Custom action (users.drafts.create)
        - Body = `{"message":{"raw":"{{rfc822_base64url}}","threadId":"{{thread_id}}"}}`
        - Satisfies Google’s three threading rules (threadId, headers, matching subject).

### Sync Drive - GCS
### Indexer
### RAG and draft