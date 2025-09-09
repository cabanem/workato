{
  title: "Workato Data Tables",
  
  # ==========================================
  # CONNECTION CONFIGURATION
  # ==========================================
  connection: {
    fields: [
      {
        name: "environment",
        label: "Environment",
        control_type: "select",
        pick_list: [
          ["Production", "app"],
          ["EU Region", "app.eu"]
        ],
        default: "app.eu",
        optional: false,
        hint: "Select your Workato environment region"
      },
      {
        name: "auth_type",
        label: "Authentication Type",
        control_type: "select",
        pick_list: [
          ["API Token", "api_token"],
          ["OAuth 2.0", "oauth2"]
        ],
        default: "api_token",
        optional: false,
        hint: "Choose between API Token (simpler) or OAuth 2.0 (more secure)"
      },
      {
        name: "api_token",
        label: "API Token",
        control_type: "password",
        optional: true,
        hint: "Your Workato API token (found in Account Settings > API Tokens)",
        # ngIf: "input.auth_type == 'api_token'" # << this is not correct
        ngIf: "input['auth_type'] == 'api_token'" # but this is
      },
      {
        name: "client_id",
        label: "Client ID",
        control_type: "text",
        optional: true,
        hint: "OAuth Client ID from API Platform settings",
        # ngIf: "input.auth_type == 'oauth2'"
        ngIf: "input['auth_type'] == 'oauth2'"
      },
      {
        name: "client_secret",
        label: "Client Secret", 
        control_type: "password",
        optional: true,
        hint: "OAuth Client Secret (only shown once when creating API client)",
        ngIf: "input['auth_type'] == 'oauth2'"
      },
      {
        name: "email",
        label: "Account Email",
        control_type: "text",
        optional: true,
        hint: "Your Workato account email (required for API token auth)",
        ngIf: "input['auth_type'] == 'api_token'"
      },
      {
        name: "enable_retry",
        label: "Enable Auto-Retry",
        control_type: "checkbox",
        type: "boolean",
        default: true,
        optional: true,
        hint: "Automatically retry failed requests due to rate limiting"
      },
      {
        name: "max_retries",
        label: "Maximum Retries",
        type: "integer",
        default: 3,
        optional: true,
        hint: "Maximum number of retry attempts",
        #ngIf: "input.enable_retry == true"
        ngIf: "input['enable_retry'] == true"
      }
    ],
    
    authorization: {
      type: "custom_auth",
      apply: lambda do |connection|
        headers("Authorization": "Bearer #{connection['api_token']}")
      end
    },
    
    base_uri: lambda do |connection|
      "https://#{connection['environment']}.workato.com"
    end
  },
  
  # ==========================================
  # TEST CONNECTION
  # ==========================================
  test: lambda do |_connection|
    # Minimal, stable endpoints only
    me = get("/api/users/me")
    tables = get("/api/data_tables").params(page: 1, per_page: 1)

    {
      success: true,
      message: "Connected",
      account_name: me["name"] || me["id"],
      sample_table_count: (tables["data"] || []).length
    }
  rescue RestClient::ExceptionWithResponse => e
    error("Test failed (#{e.http_code}): #{e.response&.body || e.message}")
  rescue => e
    error("Test failed: #{e.message}")
  end,

  # ==========================================
  # HELPER METHODS
  # ==========================================
  methods: {
    # Global host for record APIs (not region-specific)
    records_base: lambda do |_connection|
      "https://data-tables.workato.com"
    end,

    # Hardened retry for 429
    execute_with_retry: lambda do |connection, &block|
      retries = 0
      max_retries = (connection["max_retries"] || 3).to_i
      begin
        block.call
      rescue RestClient::ExceptionWithResponse => e
        if e.http_code == 429 && connection["enable_retry"] && retries < max_retries
          hdrs = e.response&.headers || {}
          ra = hdrs["Retry-After"] || hdrs[:retry_after] || 60
          sleep(ra.to_i)
          retries += 1
          retry
        end
        raise
      end
    end,
    
    # Robust Error Handling
    handle_api_errors: lambda do |response|
      case response.code
      when 404
        error("Resource not found: #{response.request.url}")
      when 403
        error("Permission denied: You don't have access to this resource")
      when 429
        retry_after = response.headers["Retry-After"] || "60"
        error("Rate limit exceeded. Please retry after #{retry_after} seconds")
      when 400
        error("Bad request: #{response.body}")
      when 500..599
        error("Server error: #{response.message}")
      end
    end,
    
    # Input Validation
    validate_table_id: lambda do |table_id|
      error("Table ID is required") if table_id.blank?
      error("Table ID must be a positive integer") unless table_id.to_i > 0
    end,
    
    validate_row_data: lambda do |row_data, table|
      return unless table.present?
      cols = table["schema"] || []
      cols.each do |col|
        fname = col["name"]
        required = (col["optional"] == false)
        if required && (row_data[fname].nil? || row_data[fname].to_s == "")
          error("Required field missing: #{fname}")
        end
        # Optional: type checks keyed to Data Tables types (string, integer, number, boolean, date, date_time, file, relation)
      end
    end,

    validate_field_type: lambda do |value, type, field_name|
      case type
      when "integer"
        unless value.to_s.match?(/^\d+$/)
          error("Field '#{field_name}' must be an integer")
        end
      when "decimal", "float"
        unless value.to_s.match?(/^\d*\.?\d+$/)
          error("Field '#{field_name}' must be a decimal number")
        end
      when "boolean"
        unless [true, false, "true", "false", 0, 1].include?(value)
          error("Field '#{field_name}' must be a boolean")
        end
      when "datetime"
        begin
          DateTime.parse(value.to_s)
        rescue
          error("Field '#{field_name}' must be a valid datetime")
        end
      end
    end,
    
    # Pagination Helper
    paginate_all: lambda do |connection, url, params = {}|
      all_results = []
      params[:limit] ||= 100
      params[:offset] = 0
      
      loop do
        response = call(:execute_with_retry, connection) { get(url).params(params) }
        rows = response["rows"] || response["records"] || response["data"] || []

        has_more = response["has_more"] || (rows.length == params[:limit])
        break unless has_more
        params[:offset] += params[:limit]
        
        # Prevent infinite loops
        break if params[:offset] > 10000
      end
      
      all_results
    end,
    
    # Helper for building complex filters
    build_filter_query: lambda do |filters|
      return {} unless filters.present?
      
      operator = filters["operator"] || "and"
      conditions = filters["conditions"] || []
      
      if conditions.length == 1
        condition = conditions.first
        { condition["column"] => { condition["operator"] => condition["value"] } }
      else
        {
          "$#{operator}" => conditions.map do |condition|
            { condition["column"] => { condition["operator"] => condition["value"] } }
          end
        }
      end
    end,

    # Map UI filters to Data Tables `$` operators
    build_where: lambda do |filters|
      return nil unless filters.present?

      op_map = {
        "eq" => "$eq",
        "ne" => "$ne",
        "gt" => "$gt",
        "lt" => "$lt",
        "gte" => "$gte",
        "lte" => "$lte",
        "in" => "$in",
        "starts_with" => "$starts_with"
      }

      conditions = (filters["conditions"] || []).map do |c|
        next nil unless c["column"].present? && c["operator"].present?
        oper = op_map[c["operator"]]
        next nil unless oper
        val = c["value"]
        { c["column"] => { oper => val } }
      end.compact

      return nil if conditions.empty?

      if conditions.length == 1 || (filters["operator"] || "and") == "and"
        # shorthand AND allowed
        # Merge when safe (single condition) otherwise wrap in $and
        return conditions.first if conditions.length == 1
        { "$and" => conditions }
      else
        { "$or" => conditions }
      end
    end,

    # Try the canonical records query path, then the legacy one.
    records_query_call: lambda do |connection, table_id, body|
      base = call(:records_base, connection)
      primary = "#{base}/api/v1/tables/#{table_id}/records/query"
      fallback = "#{base}/api/v1/tables/#{table_id}/query"
      call(:execute_with_retry, connection) { post(primary).payload(body) }
    rescue RestClient::NotFound
      call(:execute_with_retry, connection) { post(fallback).payload(body) }
    end,

    normalize_records_result: lambda do |_connection, resp|
      {
        records: resp["records"] || resp["data"] || [],
        continuation_token: resp["continuation_token"]
      }
    end,

    # Uniform error object for batch ops
    make_error_hash: lambda do |_connection, idx, id, e|
      {
        index: idx,
        record_id: id,
        http_code: (e.respond_to?(:http_code) ? e.http_code : nil),
        message: e.message.to_s.gsub(/\s+/, " ")[0, 500],
        body: (e.respond_to?(:response) ? e.response&.body : nil)
      }
    end
  },
  
  # ==========================================
  # PICKUP VALUES (Dynamic field values)
  # ==========================================
  pick_lists: {
    tables: lambda do |_connection|
      r = get("/api/data_tables").params(page: 1, per_page: 100)
      (r["data"] || []).map { |t| [t["name"], t["id"]] }
    end,
    
    table_columns: lambda do |connection, table_id:|
      return [] unless table_id.present?
      
      table = call(:execute_with_retry, connection) { get("/api/data_tables/#{table_id}") }
      cols = table["schema"] || table.dig("data", "schema") || []
      cols.map { |col| [col["name"], col["name"]] }
    end,

    folders: lambda do |_connection|
      r = get("/api/folders").params(page: 1, per_page: 200)
      (r["data"] || []).map { |f| [f["name"], f["id"]] }
    end,

    projects: lambda do |_connection|
      r = get("/api/projects").params(page: 1, per_page: 200)
      (r["data"] || []).map { |p| [p["name"], p["id"]] }
    end
  },

  # ==========================================
  # OBJECT DEFINITIONS
  # ==========================================
  object_definitions: {
    table: {
      fields: lambda do |connection, config_fields|
        [
          { name: "id", type: "integer", label: "Table ID" },
          { name: "name", label: "Table Name" },
          { name: "description", label: "Description" },
          { name: "schema_id", type: "integer", label: "Schema ID" },
          { name: "schema", type: "array", of: "object", properties: [
            { name: "type" },
            { name: "name" },
            { name: "optional", type: "boolean" },
            { name: "field_id" },
            { name: "hint" },
            { name: "multivalue", type: "boolean" }
          ]},
          { name: "row_count", type: "integer", label: "Row Count" },
          { name: "created_at", type: "timestamp", label: "Created At" },
          { name: "updated_at", type: "timestamp", label: "Updated At" },
          { name: "created_by", label: "Created By" },
          { name: "metadata", type: "object", label: "Metadata" }
        ]
      end
    },
    
    column: {
      fields: lambda do |connection, config_fields|
        [
          { name: "name", label: "Column Name" },
          { name: "type", label: "Data Type" },
          { name: "primary_key", type: "boolean", label: "Is Primary Key" },
          { name: "required", type: "boolean", label: "Is Required" },
          { name: "unique", type: "boolean", label: "Is Unique" },
          { name: "default_value", label: "Default Value" },
          { name: "description", label: "Description" }
        ]
      end
    },
    
    row: {
      fields: lambda do |connection, config_fields|
        [
          { name: "id", type: "integer", label: "Row ID" },
          { name: "created_at", type: "timestamp", label: "Created At" },
          { name: "updated_at", type: "timestamp", label: "Updated At" },
          { name: "data", type: "object", label: "Row Data" }
        ]
      end
    },
    
    records_result: {
      fields: lambda do |_connection, _config|
        [
          { name: "records", type: "array", of: "object" },
          { name: "continuation_token" }
        ]
      end
    },

    folder: {
      fields: lambda do |_connection, _config|
        [
          { name: "id" },
          { name: "name" },
          { name: "parent_id" },
          { name: "project_id" },
          { name: "created_at", type: "timestamp" },
          { name: "updated_at", type: "timestamp" }
        ]
      end
    },

    project: {
      fields: lambda do |_connection, _config|
        [
          { name: "id" },
          { name: "name" },
          { name: "created_at", type: "timestamp" },
          { name: "updated_at", type: "timestamp" }
        ]
      end
    },

    batch_result: {
      fields: lambda do |_connection, _config|
        [
          { name: "success_count", type: "integer" },
          { name: "error_count", type: "integer" },
          { name: "results", type: "array", of: "object" },
          { name: "errors", type: "array", of: "object", properties: [
            { name: "index", type: "integer" },
            { name: "record_id" },
            { name: "http_code", type: "integer" },
            { name: "message" },
            { name: "body" }
          ] }
        ]
      end
    }
  },

  # ==========================================
  # ACTIONS
  # ==========================================
  actions: {
    # ---------- TABLES (Developer API) ----------
    # Create Table
    create_table: {
      title: "Create data table",
      input_fields: lambda do
        [
          { name: "name", optional: false },
          { name: "folder_id", type: "integer", optional: false },
          {
            name: "schema",
            type: "array", of: "object",
            optional: false,
            properties: [
              {
                name: "type",
                optional: false,
                control_type: "select",
                pick_list: [
                  ["String", "string"],
                  ["Integer", "integer"],
                  ["Number (decimal)", "number"],
                  ["Boolean", "boolean"],
                  ["Date", "date"],
                  ["Datetime", "date_time"],
                  ["File", "file"],
                  ["Relation", "relation"]
                ]
              },
              { name: "name", optional: false },
              { name: "optional", type: "boolean", default: true },
              { name: "hint", optional: true },
              { name: "default_value", optional: true },
              { name: "multivalue", type: "boolean", optional: true },
              {
                name: "relation",
                type: "object",
                optional: true,
                properties: [
                  { name: "table_id" },
                  { name: "field_id" }
                ]
              }
            ]
          }
        ]
      end,
      output_fields: lambda do |object_definitions|
        { name: "data", type: "object", properties: object_definitions["table"] }
      end,
      execute: lambda do |_connection, input|
        post("/api/data_tables").payload(
          name: input["name"],
          folder_id: input["folder_id"],
          schema: input["schema"]
        )
      end
    },
    # Update table
    update_table: {
      title: "Update data table",
      input_fields: lambda do
        [
          { name: "table_id", optional: false, control_type: "select", pick_list: "tables" },
          { name: "name", optional: true },
          { name: "folder_id", type: "integer", optional: true },
          { name: "schema", type: "array", of: "object", optional: true, properties: [
            { name: "type" }, { name: "name" },
            { name: "optional", type: "boolean" },
            { name: "hint" }, { name: "default_value" },
            { name: "multivalue", type: "boolean" },
            { name: "relation", type: "object", properties: [
              { name: "table_id" }, { name: "field_id" }
            ]}
          ]}
        ]
      end,
      output_fields: lambda do |object_definitions|
        { name: "data", type: "object", properties: object_definitions["table"] }
      end,
      execute: lambda do |_connection, input|
        body = {}
        body[:name] = input["name"] if input["name"].present?
        body[:folder_id] = input["folder_id"] if input["folder_id"].present?
        body[:schema] = input["schema"] if input["schema"].present?
        put("/api/data_tables/#{input['table_id']}").payload(body)
      end
    },
    # Truncate table (keep schema, clear rows) 
    truncate_table: {
      title: "Truncate data table",
      subtitle: "Remove all records, keep schema",
      input_fields: lambda do
        [
          { name: "table_id", optional: false, control_type: "select", pick_list: "tables" },
          { name: "confirm", type: "boolean", optional: false,
            hint: "Set to true to confirm truncation" }
        ]
      end,
      output_fields: lambda do
        [
          { name: "success", type: "boolean" },
          { name: "truncated_at", type: "timestamp" }
        ]
      end,
      execute: lambda do |_connection, input|
        error("Truncation not confirmed") unless input["confirm"] == true
        post("/api/data_tables/#{input['table_id']}/truncate")
        { success: true, truncated_at: Time.now.iso8601 }
      rescue RestClient::ExceptionWithResponse => e
        error("Failed to truncate: #{e.response&.body || e.message}")
      end
    },
    # Move table to folder/rename table 
    move_or_rename_table: {
      title: "Move/rename data table",
      subtitle: "Change folder and/or name",
      input_fields: lambda do
        [
          { name: "table_id", optional: false, control_type: "select", pick_list: "tables" },
          { name: "name", optional: true },
          { name: "folder_id", optional: true, control_type: "select", pick_list: "folders" }
        ]
      end,
      output_fields: lambda do |object_definitions|
        { name: "data", type: "object", properties: object_definitions["table"] }
      end,
      execute: lambda do |_connection, input|
        body = {}
        body[:name] = input["name"] if input["name"].present?
        body[:folder_id] = input["folder_id"] if input["folder_id"].present?
        error("Provide at least one of name/folder_id") if body.empty?

        put("/api/data_tables/#{input['table_id']}").payload(body)
      rescue RestClient::ExceptionWithResponse => e
        error("Failed to move/rename: #{e.response&.body || e.message}")
      end
    },

    # List folders/list projects
    list_folders: {
      title: "List folders",
      input_fields: lambda do
        [
          { name: "parent_id", optional: true },
          { name: "page", type: "integer", default: 1 },
          { name: "per_page", type: "integer", default: 100 }
        ]
      end,
      output_fields: lambda do |object_definitions|
        [
          { name: "data", type: "array", of: "object", properties: object_definitions["folder"] }
        ]
      end,
      execute: lambda do |_connection, input|
        params = { page: input["page"] || 1, per_page: input["per_page"] || 100 }
        params[:parent_id] = input["parent_id"] if input["parent_id"].present?
        get("/api/folders").params(params)
      rescue RestClient::ExceptionWithResponse => e
        error("Failed to list folders: #{e.response&.body || e.message}")
      end
    },
    # Create a folder 
    list_projects: {
      title: "List projects",
      input_fields: lambda do
        [
          { name: "page", type: "integer", default: 1 },
          { name: "per_page", type: "integer", default: 100 }
        ]
      end,
      output_fields: lambda do |object_definitions|
        [
          { name: "data", type: "array", of: "object", properties: object_definitions["project"] }
        ]
      end,
      execute: lambda do |_connection, input|
        get("/api/projects").params(page: input["page"] || 1, per_page: input["per_page"] || 100)
      rescue RestClient::ExceptionWithResponse => e
        error("Failed to list projects: #{e.response&.body || e.message}")
      end
    },
    create_folder: {
      title: "Create folder",
      input_fields: lambda do
        [
          { name: "name", optional: false },
          { name: "parent_id", optional: true, control_type: "select", pick_list: "folders" },
          { name: "project_id", optional: true, control_type: "select", pick_list: "projects",
            hint: "If your account organizes folders under projects" }
        ]
      end,
      output_fields: lambda do |object_definitions|
        { name: "data", type: "object", properties: object_definitions["folder"] }
      end,
      execute: lambda do |_connection, input|
        payload = { name: input["name"] }
        payload[:parent_id] = input["parent_id"] if input["parent_id"].present?
        payload[:project_id] = input["project_id"] if input["project_id"].present?
        post("/api/folders").payload(payload)
      rescue RestClient::ExceptionWithResponse => e
        error("Failed to create folder: #{e.response&.body || e.message}")
      end
    },

    # ---------- RECORDS (Data Tables API v1 on global host) ----------
    query_records: {
      title: "Query records (v1)",
      input_fields: lambda do
        [
          { name: "table_id", optional: false, control_type: "select", pick_list: "tables" },
          { name: "select", label: "Columns to select", type: "array", optional: true,
            hint: "Use field names or $UUID meta-fields: $record_id, $created_at, $updated_at" },
          { name: "filters", label: "Filters", type: "object", optional: true, properties: [
            { name: "operator", control_type: "select", pick_list: [["AND","and"],["OR","or"]], default: "and" },
            { name: "conditions", type: "array", of: "object", properties: [
              { name: "column" },
              { name: "operator", control_type: "select",
                pick_list: [
                  ["Equals", "eq"], ["Not equals", "ne"],
                  ["Greater than", "gt"], ["Less than", "lt"],
                  ["Greater or equal", "gte"], ["Less or equal", "lte"],
                  ["In list", "in"], ["Starts with", "starts_with"]
                ]
              },
              { name: "value" }
            ]}
          ]},
          { name: "order", label: "Sort", type: "object", optional: true, properties: [
            { name: "column" }, { name: "order", control_type: "select",
              pick_list: [["Ascending","asc"],["Descending","desc"]], default: "asc" },
            { name: "case_sensitive", type: "boolean", default: false }
          ]},
          { name: "limit", type: "integer", default: 100 },
          { name: "continuation_token", optional: true },
          { name: "timezone_offset_secs", type: "integer", optional: true,
            hint: "Required when comparing a datetime field to a date value" }
        ]
      end,
      output_fields: lambda do |object_definitions|
        object_definitions["records_result"]
      end,
      execute: lambda do |connection, input|
        where = call(:build_where, input["filters"])
        order = if input["order"].present? && input["order"]["column"].present?
                  { by: input["order"]["column"], order: input["order"]["order"] || "asc",
                    case_sensitive: !!input["order"]["case_sensitive"] }
                end

        body = {
          select: input["select"],
          where: where,
          order: order,
          limit: input["limit"] || 100,
          continuation_token: input["continuation_token"],
          timezone_offset_secs: input["timezone_offset_secs"]
        }.compact

        base = call(:records_base, connection)
        primary = "#{base}/api/v1/tables/#{input['table_id']}/records/query"
        fallback = "#{base}/api/v1/tables/#{input['table_id']}/query"

        resp = nil
        begin
          resp = call(:execute_with_retry, connection) { post(primary).payload(body) }
        rescue RestClient::NotFound
          resp = call(:execute_with_retry, connection) { post(fallback).payload(body) }
        end

        if resp.is_a?(Hash)
          {
            records: resp["records"] || resp["data"] || [],
            continuation_token: resp["continuation_token"]
          }
        else
          { records: Array(resp || []), continuation_token: nil }
        end

      rescue RestClient::ExceptionWithResponse => e
        error("Query failed: #{e.response&.body || e.message}")
      end
    },
    create_record: {
      title: "Create record (v1)",
      input_fields: lambda do
        [
          { name: "table_id", optional: false, control_type: "select", pick_list: "tables" },
          { name: "data", label: "Field values", type: "object", optional: false,
            hint: "Keys are field names or $UUID (e.g. \"$28c00d...\": \"Josh\")" }
        ]
      end,
      output_fields: lambda do
        [
          { name: "record_id" },
          { name: "created_at", type: "timestamp" },
          { name: "document", type: "array", of: "object" }
        ]
      end,
      execute: lambda do |connection, input|
        base = call(:records_base, connection)
        url = "#{base}/api/v1/tables/#{input['table_id']}/records"
        result = call(:execute_with_retry, connection) { post(url).payload(input["data"]) }
        # Spec shows array reply sometimes; normalize to first element/hash
        rec = result.is_a?(Array) ? (result.first || {}) : result
        {
          record_id: rec["record_id"],
          created_at: rec["created_at"],
          document: rec["document"]
        }
      end
    },
    update_record: {
      title: "Update record (v1)",
      input_fields: lambda do
        [
          { name: "table_id", optional: false, control_type: "select", pick_list: "tables" },
          { name: "record_id", optional: false, hint: "Use $record_id" },
          { name: "data", label: "Field values to update", type: "object", optional: false }
        ]
      end,
      output_fields: lambda do
        [
          { name: "document", type: "object" }
        ]
      end,
      execute: lambda do |connection, input|
        base = call(:records_base, connection)
        url = "#{base}/api/v1/tables/#{input['table_id']}/records/#{input['record_id']}"
        call(:execute_with_retry, connection) { put(url).payload(input["data"]) }
      end
    },
    delete_record: {
      title: "Delete record",
      input_fields: lambda do
        [
          { name: "table_id", optional: false, control_type: "select", pick_list: "tables" },
          { name: "record_id", optional: false }
        ]
      end,
      output_fields: lambda do
        [
          { name: "status", type: "integer" }
        ]
      end,
      execute: lambda do |connection, input|
        base = call(:records_base, connection)
        url = "#{base}/api/v1/tables/#{input['table_id']}/records/#{input['record_id']}"
        resp = call(:execute_with_retry, connection) { delete(url) }
        # Some replies return { data: { status: 200 } }
        { status: resp.dig("data","status") || 200 }
      end
    },
    # -- Batch --
    batch_create_records: {
      title: "Batch create records",
      subtitle: "Create multiple records sequentially with per-item error capture",
      input_fields: lambda do
        [
          { name: "table_id", optional: false, control_type: "select", pick_list: "tables" },
          { name: "records", type: "array", of: "object", optional: false, properties: [
            { name: "data", type: "object", optional: false,
              hint: "Field map (field name or UUID → value)" }
          ] }
        ]
      end,
      output_fields: lambda do |object_definitions|
        object_definitions["batch_result"]
      end,
      execute: lambda do |connection, input|
        base = call(:records_base, connection)
        url = "#{base}/api/v1/tables/#{input['table_id']}/records"

        successes = []
        errors = []

        (input["records"] || []).each_with_index do |rec, idx|
          begin
            res = call(:execute_with_retry, connection) { post(url).payload(rec["data"]) }
            successes << (res.is_a?(Array) ? (res.first || {}) : (res || {}))

          rescue RestClient::ExceptionWithResponse => e
            errors << call(:make_error_hash, idx, nil, e)
          rescue => e
            errors << call(:make_error_hash, idx, nil, e)
          end
        end

        {
          success_count: successes.length,
          error_count: errors.length,
          results: successes,
          errors: errors
        }
      end
    },
    batch_update_records: {
      title: "Batch update records",
      subtitle: "Update multiple records sequentially with per-item error capture",
      input_fields: lambda do
        [
          { name: "table_id", optional: false, control_type: "select", pick_list: "tables" },
          { name: "updates", type: "array", of: "object", optional: false, properties: [
            { name: "record_id", optional: false },
            { name: "data", type: "object", optional: false }
          ] }
        ]
      end,
      output_fields: lambda do |object_definitions|
        object_definitions["batch_result"]
      end,
      execute: lambda do |connection, input|
        base = call(:records_base, connection)

        successes = []
        errors = []

        (input["updates"] || []).each_with_index do |u, idx|
          begin
            url = "#{base}/api/v1/tables/#{input['table_id']}/records/#{u['record_id']}"
            res = call(:execute_with_retry, connection) { put(url).payload(u["data"]) }
            successes << (res.is_a?(Array) ? (res.first || {}) : (res || {}))
          rescue RestClient::ExceptionWithResponse => e
            errors << call(:make_error_hash, idx, u["record_id"], e)
          rescue => e
            errors << call(:make_error_hash, idx, u["record_id"], e)
          end
        end

        {
          success_count: successes.length,
          error_count: errors.length,
          results: successes,
          errors: errors
        }
      end
    },
    batch_delete_records: {
      title: "Batch delete records",
      subtitle: "Delete multiple records sequentially with per-item error capture",
      input_fields: lambda do
        [
          { name: "table_id", optional: false, control_type: "select", pick_list: "tables" },
          { name: "record_ids", type: "array", of: "string", optional: false }
        ]
      end,
      output_fields: lambda do |object_definitions|
        object_definitions["batch_result"]
      end,
      execute: lambda do |connection, input|
        base = call(:records_base, connection)

        successes = []
        errors = []

        (input["record_ids"] || []).each_with_index do |rid, idx|
          begin
            url = "#{base}/api/v1/tables/#{input['table_id']}/records/#{rid}"
            resp = call(:execute_with_retry, connection) { delete(url) }
            { status: resp.dig("data", "status") || 200 }

          rescue RestClient::ExceptionWithResponse => e
            errors << call(:make_error_hash, idx, rid, e)
          rescue => e
            errors << call(:make_error_hash, idx, rid, e)
          end
        end

        {
          success_count: successes.length,
          error_count: errors.length,
          results: successes,
          errors: errors
        }
      end
    },
    query_records_paged: {
      title: "Query records (paged)",
      subtitle: "Returns records and a continuation token for the next page",
      input_fields: lambda do
        [
          { name: "table_id", optional: false, control_type: "select", pick_list: "tables" },
          { name: "select", type: "array", optional: true },
          { name: "filters", type: "object", optional: true, properties: [
            { name: "operator", control_type: "select",
              pick_list: [["AND","and"],["OR","or"]], default: "and" },
            { name: "conditions", type: "array", of: "object", properties: [
              { name: "column" },
              { name: "operator", control_type: "select",
                pick_list: [
                  ["Equals","eq"],["Not equals","ne"],
                  ["Greater than","gt"],["Less than","lt"],
                  ["Greater or equal","gte"],["Less or equal","lte"],
                  ["In list","in"],["Starts with","starts_with"]
                ] },
              { name: "value" }
            ] }
          ] },
          { name: "order", type: "object", optional: true, properties: [
            { name: "column" },
            { name: "order", control_type: "select",
              pick_list: [["Ascending","asc"],["Descending","desc"]], default: "asc" },
            { name: "case_sensitive", type: "boolean", default: false }
          ] },
          { name: "limit", type: "integer", default: 100 },
          { name: "timezone_offset_secs", type: "integer", optional: true }
        ]
      end,
      output_fields: lambda do |object_definitions|
        object_definitions["records_result"]
      end,
      execute: lambda do |connection, input|
        where = call(:build_where, input["filters"])
        order = if input["order"].present? && input["order"]["column"].present?
          { by: input["order"]["column"],
            order: input["order"]["order"] || "asc",
            case_sensitive: !!input["order"]["case_sensitive"] }
        end

        body = {
          select: input["select"],
          where: where,
          order: order,
          limit: input["limit"] || 100,
          timezone_offset_secs: input["timezone_offset_secs"]
        }.compact

        resp = call(:records_query_call, connection, input["table_id"], body)
        call(:normalize_records_result, connection, resp)
      rescue RestClient::ExceptionWithResponse => e
        error("Query failed: #{e.response&.body || e.message}")
      end
    },
    query_records_next_page: {
      title: "Query records – next page",
      subtitle: "Use continuation token from the previous query",
      input_fields: lambda do
        [
          { name: "table_id", optional: false, control_type: "select", pick_list: "tables" },
          { name: "continuation_token", optional: false },
          { name: "limit", type: "integer", optional: true }
        ]
      end,
      output_fields: lambda do |object_definitions|
        object_definitions["records_result"]
      end,
      execute: lambda do |connection, input|
        body = {
          continuation_token: input["continuation_token"],
          limit: input["limit"]
        }.compact

        resp = call(:records_query_call, connection, input["table_id"], body)
        call(:normalize_records_result, connection, resp)
      rescue RestClient::ExceptionWithResponse => e
        error("Next page failed: #{e.response&.body || e.message}")
      end
    }
    # -- File Column --
    # Generate upload link
    # Attach uploaded file to record
    # Generate download link for file field
    # Download file content (streaming)
  }
}