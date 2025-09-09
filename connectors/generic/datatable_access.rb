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
      
      acquire: lambda do |connection|
        if connection["auth_type"] == "api_token"
          {
            api_token: connection["api_token"],
            email: connection["email"]
          }
        else
          # OAuth 2.0 flow
          response = post("https://#{connection['environment']}.workato.com/oauth/token").
            payload(
              grant_type: "client_credentials",
              client_id: connection["client_id"],
              client_secret: connection["client_secret"]
            ).
            request_format_www_form_urlencoded
          
          {
            access_token: response["access_token"],
            token_type: response["token_type"],
            expires_in: response["expires_in"],
            refresh_token: response["refresh_token"]
          }
        end
      end,
      
      refresh: lambda do |connection, refresh_token|
        if connection["auth_type"] == "oauth2" && refresh_token.present?
          response = post("https://#{connection['environment']}.workato.com/oauth/token").
            payload(
              grant_type: "refresh_token",
              refresh_token: refresh_token,
              client_id: connection["client_id"],
              client_secret: connection["client_secret"]
            ).
            request_format_www_form_urlencoded
          
          {
            access_token: response["access_token"],
            token_type: response["token_type"],
            expires_in: response["expires_in"],
            refresh_token: response["refresh_token"]
          }
        end
      end,
      
      apply: lambda do |connection, access_token|
        if connection["auth_type"] == "api_token"
          headers(
            "X-USER-TOKEN": access_token["api_token"],
            "X-USER-EMAIL": access_token["email"]
          )
        else
          headers("Authorization": "Bearer #{access_token['access_token']}")
        end
      end
    },
    
    base_uri: lambda do |connection|
      "https://#{connection['environment']}.workato.com"
    end
  },
  
  # ==========================================
  # TEST CONNECTION
  # ==========================================
  test: lambda do |connection|
    # Test basic connectivity
    begin
      user_info = call(:execute_with_retry, connection, :get, "/api/user")

      {
        success: true,
        message: "Connection successful!",
        account: user_info["email"] || "Unknown",
        workspace: user_info["workspace_name"] || "Default"
      }

    rescue => e
      error("Connection failed: #{e.message}")
    end
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
    
    validate_row_data: lambda do |row_data, schema|
      return unless schema.present?
      
      schema["columns"].each do |column|
        if column["required"] && row_data[column["name"]].blank?
          error("Required field missing: #{column['name']}")
        end
        
        # Type validation
        if row_data[column["name"]].present?
          call(:validate_field_type, row_data[column["name"]], column["type"], column["name"])
        end
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
        response = call(:execute_with_retry, connection, :get, url, params: params)
        all_results.concat(response["rows"])
        
        break unless response["has_more"]
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
      
      schema = call(:execute_with_retry, connection, :get, "/api/data_tables/#{table_id}/schema")
      schema["columns"].map { |col| [col["name"], col["name"]] }
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
    }
  },

  # ==========================================
  # ACTIONS
  # ==========================================
  actions: {
    # ==== TABLES (Developer API) ===
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
    # Truncate table (keep schema, clear rows) ::TODO::@cabanem
    # - API: POST /api/data_tables/:data_table_id/truncate
    
    # Move table to folder/rename table ::TODO::@cabanem
    # - API: PUT /api/data_tables/:data_table_id
    
    # List folders/list projects ::TODO::@cabanem
    # - API: GET /api/folders && GET /api/projects 
    
    # Create a folder ::TODO::@cabanem
    # - API: POST /api/folders

    # === RECORDS ===
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
                  {
                    by: input["order"]["column"],
                    order: input["order"]["order"] || "asc",
                    case_sensitive: !!input["order"]["case_sensitive"]
                  }
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
        # Docs conflict: try /records/query first, then fallback to /query
        primary = "#{base}/api/v1/tables/#{input['table_id']}/records/query"
        fallback = "#{base}/api/v1/tables/#{input['table_id']}/query"

        resp = call(:execute_with_retry, connection) { post(primary).payload(body) }
      rescue RestClient::NotFound
        resp = call(:execute_with_retry, connection) { post(fallback).payload(body) }
      ensure
        if resp.is_a?(Hash)
          {
            records: resp["records"] || resp["data"] || resp["select"] || [],
            continuation_token: resp["continuation_token"]
          }
        else
          # Some endpoints return arrays; normalize
          { records: Array.wrap(resp), continuation_token: nil }
        end
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
    }
    # -- Batch --
    # Batch create ::TODO::@cabanem
    # - input:  array of payloads
    # - output: success, per-item errors)
    # - useful: eliminates loops in recipes; you can add concurrency and partial‑failure reporting
    
    # Batch update ::TODO::@cabanem
    # - input: list of {record_id, data}
    # - iterate PUT /records/:record_id
    # - useful: bulk corrections, migrations
    
    # Batch delete ::TODO::@cabanem
    # - input: list of record IDs
    # iterate DELETE /records/:record_id
    # - useful: predictable cleanups w/guardrails
    
    # -- Query UX --
    # Query (paged) + get next page (for each) ::TODO::@cabanem
    # - first action returns 'continuation_token',
    # - second accepts token to fetch next slice 
    
    # -- File Column --
    # Generate upload link
    # Attach uploaded file to record
    # Generate download link for file field
    # Download file content (streaming)
  }
}