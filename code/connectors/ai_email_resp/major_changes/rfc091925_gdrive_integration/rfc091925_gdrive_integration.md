# Google Drive Integration Tasks for RAG Document Processing

**Project Context**

> We're building a RAG email response system that needs to process documents from Google Drive. We have existing Vertex AI and RAG_Utils connectors that need Drive integration.

---

## Components

### 1. Add OAuth2 Drive Scope

Priority: **CRITICAL (must do first)**

#### Request:
> Modify the OAuth2 authorization in the Vertex AI connector to include Google Drive read-only access. Find the `authorization_url` lambda in the connection section and add the Drive scope to the existing scopes array."

#### Requirements:
- Add `https://www.googleapis.com/auth/drive.readonly` to the scopes array
- Maintain existing Vertex AI scope
- Ensure scopes are space-separated in the final URL

#### Success Criteria:
- [ ] OAuth2 flow requests both Vertex AI and Drive permissions
- [ ] Test connection can access both APIs
- [ ] No breaking changes to existing Vertex AI functionality

---

### 2. Implement fetch_drive_file Action

Priority: **HIGH** (core functionality)

#### Request:
> Create a new action in the Vertex AI connector called `fetch_drive_file` that downloads a file from Google Drive and extracts its text content. The action should handle both Google Workspace files (Docs, Sheets) and regular files (PDFs, text).

#### Requirements:
- Input fields needed:
  - file_id: string (required) - accepts ID or full Drive URL
  - export_format: select dropdown with options ['Plain text', 'text/plain'], ['Original', 'original']
  
- Output fields needed:
  - file_id, file_name, mime_type, text_content, checksum, modified_time
  
- API endpoints to use:
  - Metadata: GET https://www.googleapis.com/drive/v3/files/{fileId}
  - Export (for Google files): GET https://www.googleapis.com/drive/v3/files/{fileId}/export?mimeType=text/plain
  - Download (for binary): GET https://www.googleapis.com/drive/v3/files/{fileId}?alt=media

#### Key Implementation Points:
- Extract file ID from URL using regex: `/[-\w]{25,}/`
- Check MIME type to determine if export or download
- Force UTF-8 encoding on text content
- Include MD5 checksum for change detection

#### Success Criteria:
- [ ] Successfully fetches Google Docs as plain text
- [ ] Successfully fetches regular text files
- [ ] Returns structured metadata for downstream processing
- [ ] Handles errors gracefully (404, 403, etc.)

---

### 3. Implement list_drive_files Action

Priority: **HIGH** (required for batch processing)

#### Request:
> Create a `list_drive_files` action that retrieves a filtered list of files from Google Drive. This will be used to monitor folders for new/updated documents.

#### Requirements:
- Input fields needed:
  - folder_id: string (optional) - blank means root folder
  - modified_after: datetime (optional) - for incremental processing
  - mime_types: array of strings (optional) - filter by file type
  - max_results: integer (default: 100)

- Output fields needed:
  - files: array containing [id, name, mimeType, size, modifiedTime]
  - count: total files returned
  - has_more: boolean indicating pagination needed

#### Query Building Logic:
- Build Drive API query string:
  - Always include: "trashed = false"
  - If folder_id: add "'folder_id' in parents"  
  - If modified_after: add "modifiedTime > '2024-01-01T00:00:00Z'"
  - If mime_types: add "(mimeType='type1' or mimeType='type2')"

#### Success Criteria:
- [ ] Lists files from specified folder
- [ ] Filters work correctly (date, MIME type)
- [ ] Returns proper file metadata
- [ ] Handles empty results gracefully

---

### 4. Implement batch_fetch_drive_files Action

Priority: **MEDIUM** (erformance optimization)

#### Request:
> Create a `batch_fetch_drive_files` action that efficiently fetches multiple Drive files in a single action, with error handling for individual file failures.

#### Requirements:
- Input fields needed:
  - file_ids: array of strings (required)
  - skip_errors: boolean (default: true) - continue if individual files fail
  - export_format: string (default: 'text/plain')

- Output fields needed:
  - successful_files: array of file objects with content
  - failed_files: array with file_id and error message
  - total_processed: integer
  - success_rate: percentage

#### Implementation Notes:
- Process files sequentially (Drive API doesn't support true batch)
- Track successes and failures separately
- If skip_errors is false, fail fast on first error
- Include timing metrics for performance monitoring

#### Success Criteria:
- [ ] Processes multiple files in one action
- [ ] Continues processing when skip_errors is true
- [ ] Provides detailed error reporting
- [ ] Returns all successfully fetched content

---

### 5. Add Drive Test to test_connection Action

Priority: **MEDIUM** (Debugging support)

#### Request:
> Extend the existing `test_connection` action (or create one if it doesn't exist) to include Google Drive API testing alongside Vertex AI testing.

#### Requirements:
Add to the test:
- Test Drive connectivity:
  1. List one file to verify basic access
  2. Check if files are found
  3. Test file read permission (if files exist)
  4. Report specific permission errors

- Expected output additions:
  - drive_access: 'connected' or 'failed'
  - drive_permissions: array of validated permissions
  - sample_file: (if verbose mode and files exist)
  - drive_errors: specific error messages

#### Success Criteria:
- [ ] Tests both Vertex AI and Drive in one action
- [ ] Identifies specific permission issues
- [ ] Provides actionable error messages
- [ ] Works for both OAuth2 and service account auth

---

### 6. Implement monitor_drive_changes Action

Priority: **LOW** (advanced feature)

#### Request:
> Implement a `monitor_drive_changes` action using Google Drive's changes API for efficient incremental processing. This replaces polling with change tracking.

#### Requirements:
- Input fields needed:
  - page_token: string (optional) - from previous run
  - folder_id: string (optional) - specific folder to monitor

- Output fields needed:
  - changes: array of change objects
  - new_page_token: string - store for next run
  - files_added: array of new files
  - files_modified: array of updated files
  - files_removed: array of deleted file IDs

#### Implementation Flow:
1. If no page_token, get startPageToken
2. Query changes API with token
3. Categorize changes (added/modified/removed)
4. Return new token for next run

#### Success Criteria:
- [ ] Correctly tracks incremental changes
- [ ] Handles initial run (no token) properly
- [ ] Categorizes changes correctly
- [ ] Token persistence works across recipe runs

---

### 7. Create Helper Methods

Priority: **LOW** - Code organization

#### Request:
> Add these helper methods to the methods section of the Vertex AI connector to support Drive operations and reduce code duplication.

#### Methods to Add:
```ruby
methods: {
  # Extract file ID from various input formats
  extract_drive_file_id: lambda do |input|
    # Handle full URLs, sharing links, or raw IDs
    # Return standardized file ID
  end,

  # Determine export MIME type for Google Workspace files  
  get_export_mime_type: lambda do |google_mime_type|
    # Map Google MIME types to export formats
    # Return appropriate export MIME type
  end,

  # Build Drive API query string
  build_drive_query: lambda do |filters|
    # Construct query from filter parameters
    # Return formatted query string
  end,

  # Handle Drive API errors with context
  handle_drive_error: lambda do |code, body, message|
    # Provide user-friendly error messages
    # Include remediation suggestions
  end
}
```

#### Success Criteria:
- [ ] Methods are reusable across actions
- [ ] Error handling is consistent
- [ ] Code duplication is minimized

---

## Testing Checklist

1. Connection Testing
```
1. Re-authenticate with new OAuth2 scope
2. Run test_connection action
3. Verify both APIs are accessible
```

2. Single File Operations
```
1. Test fetch_drive_file with a Google Doc
2. Test fetch_drive_file with a PDF
3. Test list_drive_files on your document folder
4. Verify text extraction quality
```

3. Batch Operations
```
1. List 10+ files from a folder
2. Batch fetch 5 files
3. Verify error handling with invalid file ID
4. Test with mixed file types
```

4. Integration Testing
```
1. Complete document processing pipeline:
   - Fetch file from Drive
   - Send to RAG_Utils for chunking
   - Generate embeddings
   - Store in vector index
2. Verify end-to-end data flow
3. Test error scenarios
```

---

## Acceptance Criteria for Complete Integration 

- [ ] Can authenticate with both Vertex AI and Drive APIs
- [ ] Can list files from specified Drive folders
- [ ] Can fetch and extract text from Google Docs
- [ ] Can fetch and identify PDFs for separate processing
- [ ] Can process multiple files in batch
- [ ] Error handling provides actionable messages
- [ ] Test action validates all permissions
- [ ] Change monitoring works for incremental updates
- [ ] Integration with existing RAG pipeline is seamless

---

## Code Review Checklist 

- [ ] All API responses are checked for errors
- [ ] Nil/empty values are handled gracefully
- [ ] File IDs are validated before API calls
- [ ] Text encoding is properly handled (UTF-8)
- [ ] Rate limiting is considered
- [ ] Authentication errors are clearly reported
- [ ] Methods follow Workato SDK patterns
- [ ] Output fields match the documented schema
