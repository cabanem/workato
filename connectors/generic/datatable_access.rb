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
      title: "Delete record (v1)",
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
    
    # DEPRECATED
    delete_table: {
      title: "Delete data table",
      deprecated: true,
      subtitle: "Permanently delete a data table and all its data",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables",
            hint: "The ID of the data table to delete" },
          { name: "confirm", label: "Confirm Deletion", type: "boolean", 
            optional: false,
            hint: "Set to true to confirm permanent table deletion" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "success", type: "boolean", label: "Success" },
          { name: "message", label: "Message" },
          { name: "deleted_at", type: "timestamp", label: "Deleted At" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        unless input["confirm"] == true
          error("Deletion not confirmed. Set 'confirm' to true to delete the table.")
        end
        
        call(:execute_with_retry, connection, :delete, "/api/data_tables/#{input['table_id']}")
        
        {
          success: true,
          message: "Table deleted successfully",
          deleted_at: Time.now.iso8601
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to delete table: #{e.message}")
      end
    },
    get_table_schema: {
      title: "Get table schema",
      deprecated: true,
      subtitle: "Get the schema/structure of a data table",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables",
            hint: "The ID of the data table" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "id", type: "integer", label: "Schema ID" },
          { name: "name", label: "Table Name" },
          { name: "columns", type: "array", of: "object",
            properties: object_definitions["column"] }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        call(:execute_with_retry, connection, :get, "/api/data_tables/#{input['table_id']}/schema")
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to get schema: #{e.message}")
      end
    },
    search_rows_advanced: {
      title: "Search rows (Advanced)",
      deprecated: true,
      subtitle: "Search for rows with complex AND/OR filtering",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "filters", label: "Filter Conditions", type: "object", 
            optional: true, properties: [
              { name: "operator", label: "Logic Operator", control_type: "select",
                pick_list: [["AND", "and"], ["OR", "or"]], 
                default: "and", optional: true },
              { name: "conditions", label: "Conditions", type: "array", 
                of: "object", properties: [
                  { name: "column", label: "Column Name" },
                  { name: "operator", label: "Comparison Operator", 
                    control_type: "select",
                    pick_list: [
                      ["Equals", "eq"],
                      ["Not Equals", "ne"],
                      ["Greater Than", "gt"],
                      ["Less Than", "lt"],
                      ["Greater or Equal", "gte"],
                      ["Less or Equal", "lte"],
                      ["Contains", "contains"],
                      ["Starts With", "starts_with"],
                      ["Ends With", "ends_with"],
                      ["In List", "in"],
                      ["Not In List", "not_in"],
                      ["Is Null", "is_null"],
                      ["Is Not Null", "is_not_null"]
                    ]},
                  { name: "value", label: "Value" }
                ]}
            ]},
          { name: "sort_by", label: "Sort By", type: "array", of: "object",
            optional: true, properties: [
              { name: "column", label: "Column" },
              { name: "order", label: "Order", control_type: "select",
                pick_list: [["Ascending", "asc"], ["Descending", "desc"]],
                default: "asc" }
            ]},
          { name: "limit", type: "integer", default: 100, optional: true },
          { name: "offset", type: "integer", default: 0, optional: true }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "rows", type: "array", of: "object" },
          { name: "total_count", type: "integer" },
          { name: "filtered_count", type: "integer" },
          { name: "has_more", type: "boolean" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        params = {
          limit: input["limit"] || 100,
          offset: input["offset"] || 0
        }
        
        # Build complex filter
        if input["filters"].present?
          filter_query = call(:build_filter_query, input["filters"])
          params[:filter] = filter_query.to_json
        end
        
        # Build sort
        if input["sort_by"].present?
          sort_parts = input["sort_by"].map do |sort|
            "#{sort['column']}:#{sort['order'] || 'asc'}"
          end
          params[:sort] = sort_parts.join(",")
        end
        
        response = call(:execute_with_retry, connection, :get, 
                       "/api/data_tables/#{input['table_id']}/rows", params: params)
        
        {
          rows: response["rows"],
          total_count: response["total"],
          filtered_count: response["rows"].length,
          has_more: response["has_more"]
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to search rows: #{e.message}")
      end
    },
    batch_update_rows: {
      title: "Batch update rows",
      deprecated: true,
      subtitle: "Update multiple rows in a single transaction",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "updates", label: "Row Updates", type: "array", 
            of: "object", optional: false, properties: [
              { name: "row_id", label: "Row ID", type: "integer", optional: false },
              { name: "data", label: "Updated Data", type: "object", optional: false }
            ]},
          { name: "transaction", label: "Use Transaction", type: "boolean", 
            default: true,
            hint: "Rollback all changes if any update fails" },
          { name: "validate", label: "Validate Data", type: "boolean",
            default: true,
            hint: "Validate data types before updating" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "updated_count", type: "integer" },
          { name: "rows", type: "array", of: "object" },
          { name: "errors", type: "array", of: "object" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          updates: input["updates"],
          transaction: input["transaction"],
          validate: input["validate"]
        }
        
        response = call(:execute_with_retry, connection, :put, 
                       "/api/data_tables/#{input['table_id']}/rows/batch", payload: payload)
        
        {
          updated_count: response["updated_count"],
          rows: response["rows"],
          errors: response["errors"] || []
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to batch update: #{e.message}")
      end
    },
    batch_delete_rows: {
      title: "Batch delete rows",
      deprecated: true,
      subtitle: "Delete multiple rows in a single transaction",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "row_ids", label: "Row IDs", type: "array", 
            of: "integer", optional: false,
            hint: "List of row IDs to delete" },
          { name: "transaction", label: "Use Transaction", type: "boolean", 
            default: true,
            hint: "Rollback all deletions if any delete fails" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "deleted_count", type: "integer" },
          { name: "success", type: "boolean" },
          { name: "errors", type: "array", of: "object" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          row_ids: input["row_ids"],
          transaction: input["transaction"]
        }
        
        response = call(:execute_with_retry, connection, :delete, 
                       "/api/data_tables/#{input['table_id']}/rows/batch", payload: payload)
        
        {
          deleted_count: response["deleted_count"],
          success: response["success"],
          errors: response["errors"] || []
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to batch delete: #{e.message}")
      end
    },
    export_table: {
      title: "Export table data",
      deprecated: true,
      subtitle: "Export table data in various formats",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "format", label: "Export Format", control_type: "select",
            pick_list: [
              ["CSV", "csv"],
              ["JSON", "json"],
              ["Excel", "xlsx"],
              ["XML", "xml"]
            ],
            default: "csv", optional: false },
          { name: "include_headers", label: "Include Headers", 
            type: "boolean", default: true,
            hint: "Include column headers in export (CSV/Excel only)" },
          { name: "columns", label: "Columns to Export", type: "array", 
            optional: true,
            hint: "Specific columns to export (leave empty for all)" },
          { name: "filter", label: "Filter", type: "object", optional: true,
            hint: "Filter conditions to apply before export" },
          { name: "encoding", label: "File Encoding", control_type: "select",
            pick_list: [
              ["UTF-8", "utf-8"],
              ["UTF-16", "utf-16"],
              ["ASCII", "ascii"]
            ],
            default: "utf-8", optional: true }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "file_url", label: "Download URL" },
          { name: "file_size", type: "integer", label: "File Size (bytes)" },
          { name: "row_count", type: "integer", label: "Rows Exported" },
          { name: "expires_at", type: "timestamp", label: "URL Expires At" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          format: input["format"],
          include_headers: input["include_headers"],
          encoding: input["encoding"] || "utf-8"
        }
        payload[:columns] = input["columns"] if input["columns"].present?
        payload[:filter] = input["filter"] if input["filter"].present?
        
        response = call(:execute_with_retry, connection, :post, 
                       "/api/data_tables/#{input['table_id']}/export", payload: payload)
        
        {
          file_url: response["url"],
          file_size: response["size"],
          row_count: response["row_count"],
          expires_at: response["expires_at"]
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to export table: #{e.message}")
      end
    },
    import_table_data: {
      title: "Import table data",
      deprecated: true,
      subtitle: "Import data from file into table",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "file_content", label: "File Content", optional: false,
            hint: "Base64 encoded file content or file URL" },
          { name: "format", label: "File Format", control_type: "select",
            pick_list: [
              ["CSV", "csv"],
              ["JSON", "json"],
              ["Excel", "xlsx"]
            ],
            optional: false },
          { name: "mode", label: "Import Mode", control_type: "select",
            pick_list: [
              ["Append", "append"],
              ["Replace", "replace"],
              ["Upsert", "upsert"]
            ],
            default: "append", optional: false,
            hint: "Append: Add new rows, Replace: Clear table first, Upsert: Update or insert" },
          { name: "key_column", label: "Key Column for Upsert", 
            optional: true,
            hint: "Column to use as key for upsert mode" },
          { name: "column_mapping", label: "Column Mapping", type: "object",
            optional: true,
            hint: "Map file columns to table columns {file_column: table_column}" },
          { name: "skip_rows", label: "Skip Rows", type: "integer",
            default: 0, optional: true,
            hint: "Number of rows to skip from the beginning" },
          { name: "validate", label: "Validate Data", type: "boolean",
            default: true,
            hint: "Validate data types before importing" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "imported_count", type: "integer", label: "Rows Imported" },
          { name: "updated_count", type: "integer", label: "Rows Updated" },
          { name: "skipped_count", type: "integer", label: "Rows Skipped" },
          { name: "errors", type: "array", of: "object", label: "Import Errors" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          file_content: input["file_content"],
          format: input["format"],
          mode: input["mode"],
          skip_rows: input["skip_rows"] || 0,
          validate: input["validate"]
        }
        payload[:key_column] = input["key_column"] if input["key_column"].present?
        payload[:column_mapping] = input["column_mapping"] if input["column_mapping"].present?
        
        response = call(:execute_with_retry, connection, :post, 
                       "/api/data_tables/#{input['table_id']}/import", payload: payload)
        
        {
          imported_count: response["imported_count"],
          updated_count: response["updated_count"] || 0,
          skipped_count: response["skipped_count"] || 0,
          errors: response["errors"] || []
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to import data: #{e.message}")
      end
    },
    aggregate_data: {
      title: "Aggregate table data",
      deprecated: true,
      subtitle: "Perform aggregation operations on table data",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "aggregations", label: "Aggregations", type: "array", 
            of: "object", optional: false, properties: [
              { name: "function", label: "Aggregation Function", 
                control_type: "select",
                pick_list: [
                  ["Count", "count"],
                  ["Count Distinct", "count_distinct"],
                  ["Sum", "sum"],
                  ["Average", "avg"],
                  ["Minimum", "min"],
                  ["Maximum", "max"],
                  ["Standard Deviation", "stddev"],
                  ["Variance", "variance"]
                ], optional: false },
              { name: "column", label: "Column Name", optional: true,
                hint: "Column to aggregate (not needed for COUNT)" },
              { name: "alias", label: "Result Alias", optional: false }
            ]},
          { name: "group_by", label: "Group By Columns", type: "array",
            optional: true,
            hint: "Columns to group results by" },
          { name: "having", label: "Having Conditions", type: "object",
            optional: true,
            hint: "Filter conditions for grouped results" },
          { name: "filter", label: "Where Conditions", type: "object",
            optional: true,
            hint: "Filter conditions before aggregation" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "results", type: "array", of: "object" },
          { name: "row_count", type: "integer" },
          { name: "execution_time_ms", type: "integer" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          aggregations: input["aggregations"]
        }
        payload[:group_by] = input["group_by"] if input["group_by"].present?
        payload[:having] = input["having"] if input["having"].present?
        payload[:filter] = input["filter"] if input["filter"].present?
        
        response = call(:execute_with_retry, connection, :post, 
                       "/api/data_tables/#{input['table_id']}/aggregate", payload: payload)
        
        {
          results: response["results"],
          row_count: response["row_count"],
          execution_time_ms: response["execution_time_ms"]
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to aggregate data: #{e.message}")
      end
    },
   add_column: {
      title: "Add column to table",
      deprecated: true,
      subtitle: "Add a new column to an existing table",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "column_name", label: "Column Name", optional: false },
          { name: "column_type", label: "Data Type", control_type: "select",
            pick_list: [
              ["String", "string"],
              ["Integer", "integer"],
              ["Decimal", "decimal"],
              ["Boolean", "boolean"],
              ["Datetime", "datetime"],
              ["Text", "text"],
              ["JSON", "json"]
            ], optional: false },
          { name: "default_value", label: "Default Value", optional: true },
          { name: "required", label: "Required", type: "boolean", 
            default: false },
          { name: "unique", label: "Unique", type: "boolean", 
            default: false },
          { name: "description", label: "Description", optional: true },
          { name: "after_column", label: "Position After Column", 
            optional: true,
            hint: "Name of column to position this after" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "success", type: "boolean" },
          { name: "column", type: "object", 
            properties: object_definitions["column"] }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          name: input["column_name"],
          type: input["column_type"],
          required: input["required"],
          unique: input["unique"]
        }
        payload[:default_value] = input["default_value"] if input["default_value"].present?
        payload[:description] = input["description"] if input["description"].present?
        payload[:after] = input["after_column"] if input["after_column"].present?
        
        response = call(:execute_with_retry, connection, :post, 
                       "/api/data_tables/#{input['table_id']}/columns", payload: payload)
        
        {
          success: true,
          column: response
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to add column: #{e.message}")
      end
    },
    drop_column: {
      title: "Remove column from table",
      subtitle: "Remove a column from an existing table",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" },
          { 
            name: "column_name",
            label: "Column Name",
            optional: false,
            control_type: "select", 
            pick_list: lambda do |connection, table_id:|
              return [] unless table_id.present?
              schema = get("/api/data_tables/#{table_id}/schema")
              schema["columns"].map { |col| [col["name"], col["name"]] }
            end
          },
          { name: "confirm", label: "Confirm Deletion", type: "boolean",
            optional: false,
            hint: "Set to true to confirm column deletion" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "success", type: "boolean" },
          { name: "message" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        unless input["confirm"] == true
          error("Column deletion not confirmed. Set 'confirm' to true.")
        end
        
        call(:execute_with_retry, connection, :delete, 
             "/api/data_tables/#{input['table_id']}/columns/#{input['column_name']}")
        
        {
          success: true,
          message: "Column '#{input['column_name']}' removed successfully"
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to drop column: #{e.message}")
      end
    },
    clone_table: {
      title: "Clone table",
      subtitle: "Create a copy of an existing table",
      
      input_fields: lambda do
        [
          { name: "source_table_id", label: "Source Table ID", 
            type: "integer", optional: false,
            control_type: "select", pick_list: "tables" },
          { name: "new_table_name", label: "New Table Name", 
            optional: false },
          { name: "clone_data", label: "Clone Data", type: "boolean",
            default: true,
            hint: "Copy all data from source table" },
          { name: "clone_indexes", label: "Clone Indexes", type: "boolean",
            default: true,
            hint: "Copy indexes from source table" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        object_definitions["table"]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["source_table_id"])
        
        payload = {
          name: input["new_table_name"],
          clone_data: input["clone_data"],
          clone_indexes: input["clone_indexes"]
        }
        
        call(:execute_with_retry, connection, :post, 
             "/api/data_tables/#{input['source_table_id']}/clone", payload: payload)
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to clone table: #{e.message}")
      end
    },
    get_table_audit_log: {
      title: "Get table audit log",
      subtitle: "Retrieve audit log for table changes",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "start_date", label: "Start Date", type: "timestamp",
            optional: true },
          { name: "end_date", label: "End Date", type: "timestamp",
            optional: true },
          { name: "action_types", label: "Action Types", type: "array",
            optional: true,
            hint: "Filter by action types (create, update, delete)" },
          { name: "user_email", label: "User Email", optional: true,
            hint: "Filter by user who made changes" },
          { name: "limit", type: "integer", default: 100 }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "entries", type: "array", of: "object", properties: [
            { name: "id", type: "integer" },
            { name: "action", label: "Action Type" },
            { name: "user_email" },
            { name: "timestamp", type: "timestamp" },
            { name: "details", type: "object" },
            { name: "row_id", type: "integer" }
          ]},
          { name: "total_count", type: "integer" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        params = { limit: input["limit"] || 100 }
        params[:start_date] = input["start_date"] if input["start_date"].present?
        params[:end_date] = input["end_date"] if input["end_date"].present?
        params[:action_types] = input["action_types"].join(",") if input["action_types"].present?
        params[:user_email] = input["user_email"] if input["user_email"].present?
        
        response = call(:execute_with_retry, connection, :get, 
                       "/api/data_tables/#{input['table_id']}/audit_log", params: params)
        
        {
          entries: response["entries"],
          total_count: response["total_count"]
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to get audit log: #{e.message}")
      end
    },
    create_table_relationship: {
      title: "Create table relationship",
      subtitle: "Define foreign key relationship between tables",
      
      input_fields: lambda do
        [
          { name: "parent_table_id", label: "Parent Table", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "parent_column", label: "Parent Column", optional: false,
            control_type: "select", pick_list: "table_columns",
            pick_list_params: { table_id: "parent_table_id" } },
          { name: "child_table_id", label: "Child Table", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "child_column", label: "Child Column", optional: false,
            control_type: "select", pick_list: "table_columns",
            pick_list_params: { table_id: "child_table_id" } },
          { name: "relationship_type", label: "Relationship Type",
            control_type: "select",
            pick_list: [
              ["One to One", "one_to_one"],
              ["One to Many", "one_to_many"],
              ["Many to Many", "many_to_many"]
            ], optional: false },
          { name: "on_delete", label: "On Delete Action",
            control_type: "select",
            pick_list: [
              ["Cascade", "cascade"],
              ["Set Null", "set_null"],
              ["Restrict", "restrict"],
              ["No Action", "no_action"]
            ], default: "restrict" },
          { name: "on_update", label: "On Update Action",
            control_type: "select",
            pick_list: [
              ["Cascade", "cascade"],
              ["Set Null", "set_null"],
              ["Restrict", "restrict"],
              ["No Action", "no_action"]
            ], default: "cascade" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "relationship_id", type: "integer" },
          { name: "created_at", type: "timestamp" },
          { name: "constraint_name" }
        ]
      end,
      
      execute: lambda do |connection, input|
        payload = {
          parent_table_id: input["parent_table_id"],
          parent_column: input["parent_column"],
          child_table_id: input["child_table_id"],
          child_column: input["child_column"],
          relationship_type: input["relationship_type"],
          on_delete: input["on_delete"],
          on_update: input["on_update"]
        }
        
        call(:execute_with_retry, connection, :post, "/api/data_tables/relationships", payload: payload)
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to create relationship: #{e.message}")
      end
    },
    add_computed_column: {
      title: "Add computed column",
      subtitle: "Add a virtual column with computed values",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "column_name", label: "Column Name", optional: false },
          { name: "expression", label: "Computation Expression", optional: false,
            hint: "SQL expression for computing values (e.g., price * quantity)" },
          { name: "return_type", label: "Return Type", control_type: "select",
            pick_list: [
              ["String", "string"],
              ["Integer", "integer"],
              ["Decimal", "decimal"],
              ["Boolean", "boolean"],
              ["Datetime", "datetime"]
            ], optional: false },
          { name: "stored", label: "Store Computed Value", type: "boolean",
            default: false,
            hint: "Store computed value in database (vs compute on-the-fly)" },
          { name: "description", label: "Description", optional: true }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "success", type: "boolean" },
          { name: "column", type: "object" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          name: input["column_name"],
          expression: input["expression"],
          return_type: input["return_type"],
          stored: input["stored"],
          description: input["description"]
        }
        
        response = call(:execute_with_retry, connection, :post, 
                       "/api/data_tables/#{input['table_id']}/computed_columns", payload: payload)
        
        {
          success: true,
          column: response
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to add computed column: #{e.message}")
      end
    },
    configure_row_security: {
      title: "Configure row-level security",
      subtitle: "Set up row-level access control for a table",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "policy_name", label: "Policy Name", optional: false },
          { name: "policy_type", label: "Policy Type", control_type: "select",
            pick_list: [
              ["Read", "read"],
              ["Write", "write"],
              ["Delete", "delete"],
              ["All", "all"]
            ], optional: false },
          { name: "user_column", label: "User Column", optional: false,
            hint: "Column containing user identifier" },
          { name: "condition", label: "Access Condition", optional: false,
            hint: "SQL condition for row access (e.g., user_id = current_user())" },
          { name: "role", label: "Apply to Role", optional: true,
            hint: "Specific role to apply policy to (all roles if empty)" },
          { name: "enabled", label: "Enable Policy", type: "boolean",
            default: true }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "policy_id", type: "integer" },
          { name: "created_at", type: "timestamp" },
          { name: "enabled", type: "boolean" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          policy_name: input["policy_name"],
          policy_type: input["policy_type"],
          user_column: input["user_column"],
          condition: input["condition"],
          role: input["role"],
          enabled: input["enabled"]
        }
        
        call(:execute_with_retry, connection, :post, 
             "/api/data_tables/#{input['table_id']}/security_policies", payload: payload)
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to configure security: #{e.message}")
      end
    },
    configure_field_masking: {
      title: "Configure field masking",
      subtitle: "Set up data masking for sensitive fields",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "column_name", label: "Column to Mask", optional: false,
            control_type: "select", pick_list: "table_columns",
            pick_list_params: { table_id: "table_id" } },
          { name: "masking_type", label: "Masking Type", control_type: "select",
            pick_list: [
              ["Partial", "partial"],
              ["Full", "full"],
              ["Hash", "hash"],
              ["Encrypt", "encrypt"],
              ["Custom Pattern", "custom"]
            ], optional: false },
          { name: "masking_pattern", label: "Masking Pattern", optional: true,
            hint: "Pattern for masking (e.g., XXX-XX-#### for SSN)",
            ngIf: "input['masking_type'] == 'custom'" },
          { name: "roles_to_unmask", label: "Roles with Access", type: "array",
            optional: true,
            hint: "Roles that can see unmasked data" },
          { name: "audit_access", label: "Audit Access", type: "boolean",
            default: true,
            hint: "Log when unmasked data is accessed" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "masking_id", type: "integer" },
          { name: "column_name" },
          { name: "masking_type" },
          { name: "created_at", type: "timestamp" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          column_name: input["column_name"],
          masking_type: input["masking_type"],
          roles_to_unmask: input["roles_to_unmask"],
          audit_access: input["audit_access"]
        }
        payload[:masking_pattern] = input["masking_pattern"] if input["masking_pattern"].present?
        
        call(:execute_with_retry, connection, :post, 
             "/api/data_tables/#{input['table_id']}/field_masking", payload: payload)
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to configure masking: #{e.message}")
      end
    },
    join_tables: {
      title: "Join tables",
      subtitle: "Perform SQL-like joins between tables",
      
      input_fields: lambda do
        [
          { name: "left_table", label: "Left Table", type: "object", 
            optional: false, properties: [
              { name: "table_id", type: "integer", control_type: "select",
                pick_list: "tables" },
              { name: "alias", optional: true },
              { name: "columns", type: "array", optional: true,
                hint: "Columns to select from left table" }
            ]},
          { name: "right_table", label: "Right Table", type: "object",
            optional: false, properties: [
              { name: "table_id", type: "integer", control_type: "select",
                pick_list: "tables" },
              { name: "alias", optional: true },
              { name: "columns", type: "array", optional: true,
                hint: "Columns to select from right table" }
            ]},
          { name: "join_type", label: "Join Type", control_type: "select",
            pick_list: [
              ["Inner Join", "inner"],
              ["Left Join", "left"],
              ["Right Join", "right"],
              ["Full Outer Join", "full"],
              ["Cross Join", "cross"]
            ], default: "inner" },
          { name: "join_condition", label: "Join Condition", optional: false,
            hint: "Join condition (e.g., left.id = right.user_id)" },
          { name: "where_clause", label: "Where Clause", optional: true },
          { name: "group_by", label: "Group By", type: "array", optional: true },
          { name: "order_by", label: "Order By", type: "array", optional: true },
          { name: "limit", type: "integer", default: 100 },
          { name: "offset", type: "integer", default: 0 }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "results", type: "array", of: "object" },
          { name: "row_count", type: "integer" },
          { name: "execution_time_ms", type: "integer" }
        ]
      end,
      
      execute: lambda do |connection, input|
        payload = {
          left_table: input["left_table"],
          right_table: input["right_table"],
          join_type: input["join_type"],
          join_condition: input["join_condition"],
          where_clause: input["where_clause"],
          group_by: input["group_by"],
          order_by: input["order_by"],
          limit: input["limit"],
          offset: input["offset"]
        }
        
        response = call(:execute_with_retry, connection, :post, "/api/data_tables/join", payload: payload)
        
        {
          results: response["results"],
          row_count: response["row_count"],
          execution_time_ms: response["execution_time_ms"]
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to join tables: #{e.message}")
      end
    },
    convert_column_type: {
      title: "Convert column data type",
      subtitle: "Change the data type of an existing column",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "column_name", label: "Column Name", optional: false,
            control_type: "select", pick_list: "table_columns",
            pick_list_params: { table_id: "table_id" } },
          { name: "new_type", label: "New Data Type", control_type: "select",
            pick_list: [
              ["String", "string"],
              ["Integer", "integer"],
              ["Decimal", "decimal"],
              ["Boolean", "boolean"],
              ["Datetime", "datetime"],
              ["Text", "text"],
              ["JSON", "json"]
            ], optional: false },
          { name: "conversion_rule", label: "Conversion Rule", 
            control_type: "select",
            pick_list: [
              ["Auto Convert", "auto"],
              ["Cast", "cast"],
              ["Parse", "parse"],
              ["Custom Function", "custom"]
            ], default: "auto" },
          { name: "custom_function", label: "Custom Conversion Function",
            optional: true,
            hint: "Custom SQL function for conversion",
            ngIf: "input['conversion_rule'] == 'custom'" },
          { name: "handle_errors", label: "Error Handling", 
            control_type: "select",
            pick_list: [
              ["Fail on Error", "fail"],
              ["Set to Null", "null"],
              ["Use Default", "default"]
            ], default: "fail" },
          { name: "default_value", label: "Default Value for Errors",
            optional: true,
            ngIf: "input['handle_errors'] == 'default'" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "success", type: "boolean" },
          { name: "rows_converted", type: "integer" },
          { name: "errors", type: "array", of: "object" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          column_name: input["column_name"],
          new_type: input["new_type"],
          conversion_rule: input["conversion_rule"],
          handle_errors: input["handle_errors"]
        }
        payload[:custom_function] = input["custom_function"] if input["custom_function"].present?
        payload[:default_value] = input["default_value"] if input["default_value"].present?
        
        response = call(:execute_with_retry, connection, :put, 
                       "/api/data_tables/#{input['table_id']}/columns/#{input['column_name']}/convert", 
                       payload: payload)
        
        {
          success: response["success"],
          rows_converted: response["rows_converted"],
          errors: response["errors"] || []
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to convert column type: #{e.message}")
      end
    },
    partition_table: {
      title: "Partition table",
      deprecated: true,
      subtitle: "Create partitions for large tables",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "partition_type", label: "Partition Type", 
            control_type: "select",
            pick_list: [
              ["Range", "range"],
              ["List", "list"],
              ["Hash", "hash"],
              ["Date/Time", "datetime"]
            ], optional: false },
          { name: "partition_column", label: "Partition Column", 
            optional: false,
            control_type: "select", pick_list: "table_columns",
            pick_list_params: { table_id: "table_id" } },
          { name: "partition_count", label: "Number of Partitions",
            type: "integer", optional: true,
            hint: "For hash partitioning",
            ngIf: "input['partition_type'] == 'hash'" },
          { name: "partition_interval", label: "Partition Interval",
            control_type: "select",
            pick_list: [
              ["Daily", "day"],
              ["Weekly", "week"],
              ["Monthly", "month"],
              ["Yearly", "year"]
            ],
            ngIf: "input['partition_type'] == 'datetime'" },
          { name: "partition_ranges", label: "Partition Ranges",
            type: "array", of: "object", optional: true,
            properties: [
              { name: "name", label: "Partition Name" },
              { name: "from_value", label: "From Value" },
              { name: "to_value", label: "To Value" }
            ],
            ngIf: "input['partition_type'] == 'range'" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "success", type: "boolean" },
          { name: "partitions_created", type: "integer" },
          { name: "partition_info", type: "array", of: "object" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          partition_type: input["partition_type"],
          partition_column: input["partition_column"]
        }
        
        case input["partition_type"]
        when "hash"
          payload[:partition_count] = input["partition_count"]
        when "datetime"
          payload[:partition_interval] = input["partition_interval"]
        when "range"
          payload[:partition_ranges] = input["partition_ranges"]
        end
        
        response = call(:execute_with_retry, connection, :post, 
                       "/api/data_tables/#{input['table_id']}/partition", payload: payload)
        
        {
          success: true,
          partitions_created: response["partitions_created"],
          partition_info: response["partition_info"]
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to partition table: #{e.message}")
      end
    },
    create_index: {
      title: "Create table index",
      deprecated: true,
      subtitle: "Create an index to improve query performance",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "index_name", label: "Index Name", optional: false },
          { name: "columns", label: "Columns", type: "array", of: "object",
            optional: false, properties: [
              { name: "column_name", label: "Column Name" },
              { name: "sort_order", label: "Sort Order", 
                control_type: "select",
                pick_list: [["Ascending", "asc"], ["Descending", "desc"]],
                default: "asc" }
            ]},
          { name: "index_type", label: "Index Type", control_type: "select",
            pick_list: [
              ["B-Tree", "btree"],
              ["Hash", "hash"],
              ["GiST", "gist"],
              ["GIN", "gin"],
              ["Full Text", "fulltext"]
            ], default: "btree" },
          { name: "unique", label: "Unique Index", type: "boolean",
            default: false },
          { name: "where_clause", label: "Partial Index Condition",
            optional: true,
            hint: "Create partial index with WHERE condition" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "index_id", type: "integer" },
          { name: "index_name" },
          { name: "created_at", type: "timestamp" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          index_name: input["index_name"],
          columns: input["columns"],
          index_type: input["index_type"],
          unique: input["unique"]
        }
        payload[:where_clause] = input["where_clause"] if input["where_clause"].present?
        
        call(:execute_with_retry, connection, :post, 
             "/api/data_tables/#{input['table_id']}/indexes", payload: payload)
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to create index: #{e.message}")
      end
    },
    analyze_table_performance: {
      title: "Analyze table performance",
      deprecated: true,
      subtitle: "Get performance metrics and optimization suggestions",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "analysis_type", label: "Analysis Type", 
            control_type: "select",
            pick_list: [
              ["Full Analysis", "full"],
              ["Query Performance", "queries"],
              ["Index Usage", "indexes"],
              ["Storage Statistics", "storage"],
              ["Access Patterns", "access"]
            ], default: "full" },
          { name: "time_range", label: "Time Range", control_type: "select",
            pick_list: [
              ["Last Hour", "1h"],
              ["Last 24 Hours", "24h"],
              ["Last 7 Days", "7d"],
              ["Last 30 Days", "30d"]
            ], default: "24h" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "table_stats", type: "object", properties: [
            { name: "row_count", type: "integer" },
            { name: "table_size_mb", type: "decimal" },
            { name: "index_size_mb", type: "decimal" },
            { name: "last_vacuum", type: "timestamp" },
            { name: "last_analyze", type: "timestamp" }
          ]},
          { name: "performance_metrics", type: "object", properties: [
            { name: "avg_query_time_ms", type: "decimal" },
            { name: "slow_queries", type: "integer" },
            { name: "cache_hit_ratio", type: "decimal" },
            { name: "index_hit_ratio", type: "decimal" }
          ]},
          { name: "recommendations", type: "array", of: "object", properties: [
            { name: "priority", label: "Priority Level" },
            { name: "type", label: "Recommendation Type" },
            { name: "description" },
            { name: "estimated_improvement" }
          ]}
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        params = {
          analysis_type: input["analysis_type"],
          time_range: input["time_range"]
        }
        
        call(:execute_with_retry, connection, :get, 
             "/api/data_tables/#{input['table_id']}/performance", params: params)
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to analyze performance: #{e.message}")
      end
    },
    backup_table: {
      title: "Backup table",
      deprecated: true,
      subtitle: "Create a backup of table data and schema",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "backup_name", label: "Backup Name", optional: false },
          { name: "backup_type", label: "Backup Type", control_type: "select",
            pick_list: [
              ["Full Backup", "full"],
              ["Schema Only", "schema"],
              ["Data Only", "data"],
              ["Incremental", "incremental"]
            ], default: "full" },
          { name: "compression", label: "Enable Compression", 
            type: "boolean", default: true },
          { name: "encryption", label: "Enable Encryption",
            type: "boolean", default: false },
          { name: "retention_days", label: "Retention Days",
            type: "integer", default: 30,
            hint: "Number of days to retain backup" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "backup_id", type: "integer" },
          { name: "backup_url" },
          { name: "backup_size_mb", type: "decimal" },
          { name: "created_at", type: "timestamp" },
          { name: "expires_at", type: "timestamp" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          backup_name: input["backup_name"],
          backup_type: input["backup_type"],
          compression: input["compression"],
          encryption: input["encryption"],
          retention_days: input["retention_days"]
        }
        
        call(:execute_with_retry, connection, :post, 
             "/api/data_tables/#{input['table_id']}/backup", payload: payload)
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to create backup: #{e.message}")
      end
    },
    restore_table: {
      title: "Restore table from backup",
      deprecated: true,
      subtitle: "Restore table data and schema from a backup",
      
      input_fields: lambda do
        [
          { name: "backup_id", label: "Backup ID", type: "integer",
            optional: false },
          { name: "target_table_name", label: "Target Table Name",
            optional: false,
            hint: "Name for restored table (can be different from original)" },
          { name: "restore_type", label: "Restore Type", 
            control_type: "select",
            pick_list: [
              ["Full Restore", "full"],
              ["Schema Only", "schema"],
              ["Data Only", "data"]
            ], default: "full" },
          { name: "overwrite_existing", label: "Overwrite Existing Table",
            type: "boolean", default: false }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "table_id", type: "integer" },
          { name: "table_name" },
          { name: "rows_restored", type: "integer" },
          { name: "restored_at", type: "timestamp" }
        ]
      end,
      
      execute: lambda do |connection, input|
        payload = {
          backup_id: input["backup_id"],
          target_table_name: input["target_table_name"],
          restore_type: input["restore_type"],
          overwrite_existing: input["overwrite_existing"]
        }
        
        call(:execute_with_retry, connection, :post, "/api/data_tables/restore", payload: payload)
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to restore table: #{e.message}")
      end
    },
    create_validation_rule: {
      title: "Create validation rule",
      deprecated: true,
      subtitle: "Add data validation rules to a table",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "rule_name", label: "Rule Name", optional: false },
          { name: "rule_type", label: "Rule Type", control_type: "select",
            pick_list: [
              ["Check Constraint", "check"],
              ["Regex Pattern", "regex"],
              ["Range", "range"],
              ["List of Values", "enum"],
              ["Custom Function", "custom"]
            ], optional: false },
          { name: "columns", label: "Apply to Columns", type: "array",
            optional: false,
            hint: "Columns this rule applies to" },
          { name: "rule_expression", label: "Rule Expression", 
            optional: false,
            hint: "Validation expression or pattern" },
          { name: "error_message", label: "Error Message",
            optional: true,
            hint: "Custom error message when validation fails" },
          { name: "severity", label: "Severity", control_type: "select",
            pick_list: [
              ["Error", "error"],
              ["Warning", "warning"],
              ["Info", "info"]
            ], default: "error" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "rule_id", type: "integer" },
          { name: "created_at", type: "timestamp" },
          { name: "enabled", type: "boolean" }
        ]
      end,
      
      execute: lambda do |connection, input|
        call(:validate_table_id, input["table_id"])
        
        payload = {
          rule_name: input["rule_name"],
          rule_type: input["rule_type"],
          columns: input["columns"],
          rule_expression: input["rule_expression"],
          error_message: input["error_message"],
          severity: input["severity"]
        }
        
        call(:execute_with_retry, connection, :post, 
             "/api/data_tables/#{input['table_id']}/validation_rules", payload: payload)
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to create validation rule: #{e.message}")
      end
    }
  },
  
  # ==========================================
  # TRIGGERS
  # ==========================================
  triggers: {
    # Webhook-based triggers
    new_row_webhook: {
      title: "New row (Webhook)",
      subtitle: "Triggers instantly when a new row is added",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "columns", label: "Columns to Include", type: "array",
            optional: true,
            hint: "Specific columns to include in trigger (all if empty)" }
        ]
      end,
      
      webhook_subscribe: lambda do |webhook_url, connection, input|
        call(:validate_table_id, input["table_id"])
        
        response = call(:execute_with_retry, connection, :post, "/api/webhooks", 
          payload: {
            url: webhook_url,
            event: "data_table.row.created",
            table_id: input["table_id"],
            columns: input["columns"]
          })
        
        response  # Return the webhook object for unsubscribe
      end,
      
      webhook_unsubscribe: lambda do |webhook, connection|
        delete("/api/webhooks/#{webhook['id']}")
      end,
      
      webhook_notification: lambda do |input, payload, extended_input_schema, extended_output_schema, headers, params|
        payload
      end,
      
      dedup: lambda do |row|
        "#{row['table_id']}-#{row['id']}"
      end,
      
      output_fields: lambda do |object_definitions|
        object_definitions["row"]
      end
    },
    
    row_updated_webhook: {
      title: "Row updated (Webhook)",
      subtitle: "Triggers instantly when a row is updated",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "columns", label: "Columns to Monitor", type: "array",
            optional: true,
            hint: "Monitor changes to specific columns only" }
        ]
      end,
      
    webhook_subscribe: lambda do |webhook_url, connection, input|
      call(:validate_table_id, input["table_id"])
      
      response = call(:execute_with_retry, connection, :post, "/api/webhooks", 
        payload: {
          url: webhook_url,
          event: "data_table.row.created",
          table_id: input["table_id"],
          columns: input["columns"]
        })
      
      response  # Return the webhook object for unsubscribe
    end,
      
      webhook_unsubscribe: lambda do |webhook, connection|
        delete("/api/webhooks/#{webhook['id']}")
      end,
      
      webhook_notification: lambda do |input, payload, extended_input_schema, extended_output_schema, headers, params|
        payload
      end,
      
      dedup: lambda do |row|
        "#{row['table_id']}-#{row['id']}-#{row['updated_at']}"
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "id", type: "integer" },
          { name: "old_data", type: "object" },
          { name: "new_data", type: "object" },
          { name: "changed_columns", type: "array" },
          { name: "updated_at", type: "timestamp" },
          { name: "updated_by" }
        ]
      end
    },
    
    row_deleted_webhook: {
      title: "Row deleted (Webhook)",
      subtitle: "Triggers instantly when a row is deleted",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" }
        ]
      end,
      
      webhook_subscribe: lambda do |webhook_url, connection, input|
        call(:validate_table_id, input["table_id"])
        
        response = call(:execute_with_retry, connection, :post, "/api/webhooks",
          payload: {
            url: webhook_url,
            event: "data_table.row.deleted",
            table_id: input["table_id"]
          })

        response
      end,
      
      webhook_unsubscribe: lambda do |webhook, connection|
        delete("/api/webhooks/#{webhook['id']}")
      end,
      
      webhook_notification: lambda do |input, payload, extended_input_schema, extended_output_schema, headers, params|
        payload
      end,
      
      dedup: lambda do |row|
        "#{row['table_id']}-#{row['id']}-#{row['deleted_at']}"
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "id", type: "integer" },
          { name: "deleted_data", type: "object" },
          { name: "deleted_at", type: "timestamp" },
          { name: "deleted_by" }
        ]
      end
    },
    
    table_schema_changed: {
      title: "Table schema changed",
      subtitle: "Triggers when table structure is modified",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" }
        ]
      end,
      
      webhook_subscribe: lambda do |webhook_url, connection, input|
        call(:validate_table_id, input["table_id"])
        
        response = call(:execute_with_retry, connection, :post, "/api/webhooks",
          payload: {
            url: webhook_url,
            event: "data_table.schema.changed",
            table_id: input["table_id"]
          })

        response
      end,
      
      webhook_unsubscribe: lambda do |webhook, connection|
        delete("/api/webhooks/#{webhook['id']}")
      end,
      
      webhook_notification: lambda do |input, payload, extended_input_schema, extended_output_schema, headers, params|
        payload
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "table_id", type: "integer" },
          { name: "change_type" },
          { name: "old_schema", type: "object" },
          { name: "new_schema", type: "object" },
          { name: "changed_at", type: "timestamp" },
          { name: "changed_by" }
        ]
      end
    },
    
    # Polling trigger 
    new_row_poll: {
      title: "New row (Polling)",
      subtitle: "Checks for new rows periodically",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "since", type: "timestamp", optional: true,
            hint: "Get rows created after this time" },
          { name: "batch_size", type: "integer", default: 100,
            hint: "Number of rows to fetch per poll" }
        ]
      end,
      
      poll: lambda do |connection, input, last_poll|
        call(:validate_table_id, input["table_id"])
        
        # Time methods aren't available in this contex
        # since = last_poll || input["since"] || 1.hour.ago
        since = last_poll || input["since"] || (Time.now - 3600).iso8601
        
        params = {
          filter: { created_at: { gt: since } }.to_json,
          sort: "created_at:asc",
          limit: input["batch_size"] || 100
        }
        
        response = call(:execute_with_retry, connection, :get, 
                       "/api/data_tables/#{input['table_id']}/rows", params: params)
        
        {
          events: response["rows"],
          next_poll: response["rows"].last&.dig("created_at") || since,
          can_poll_more: response["has_more"]
        }
      end,
      
      dedup: lambda do |row|
        "#{row['id']}"
      end,
      
      output_fields: lambda do |object_definitions|
        object_definitions["row"]
      end
    },

    # Scheduled Data Export
    scheduled_export: {
      title: "Scheduled table export",
      subtitle: "Triggers on a schedule to export table data",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "schedule", label: "Schedule", control_type: "select",
            pick_list: [
              ["Every Hour", "hourly"],
              ["Daily", "daily"],
              ["Weekly", "weekly"],
              ["Monthly", "monthly"]
            ], optional: false },
          { name: "export_format", label: "Export Format", 
            control_type: "select",
            pick_list: [["CSV", "csv"], ["JSON", "json"], ["Excel", "xlsx"]],
            default: "csv" },
          { name: "filter", label: "Export Filter", type: "object",
            optional: true,
            hint: "Filter data before export" }
        ]
      end,
      
      poll: lambda do |connection, input, last_poll|
        # Check if it's time to export based on schedule
        schedule_met = case input["schedule"]
        when "hourly"
          Time.now.min == 0
        when "daily"
          Time.now.hour == 0 && Time.now.min == 0
        when "weekly"
          Time.now.wday == 1 && Time.now.hour == 0
        when "monthly"
          Time.now.day == 1 && Time.now.hour == 0
        end
        
        if schedule_met
          response = call(:with_rate_limit_retry, connection) do
            post("/api/data_tables/#{input['table_id']}/export").
              payload(
                format: input["export_format"],
                filter: input["filter"]
              )
          end
          
          {
            events: [response],
            next_poll: Time.now
          }
        else
          {
            events: [],
            next_poll: last_poll || Time.now
          }
        end
      end,
      
      dedup: lambda do |export|
        "#{export['table_id']}-#{export['created_at']}"
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "file_url" },
          { name: "file_size", type: "integer" },
          { name: "row_count", type: "integer" },
          { name: "exported_at", type: "timestamp" }
        ]
      end
    },
    
    # Data Quality Monitor
    data_quality_alert: {
      title: "Data quality alert",
      subtitle: "Triggers when data quality issues are detected",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "quality_checks", label: "Quality Checks", 
            type: "array", of: "object", properties: [
              { name: "check_type", control_type: "select",
                pick_list: [
                  ["Null Values", "nulls"],
                  ["Duplicates", "duplicates"],
                  ["Data Type Mismatch", "type_mismatch"],
                  ["Outliers", "outliers"],
                  ["Missing Required", "missing_required"]
                ]},
              { name: "column" },
              { name: "threshold", type: "decimal",
                hint: "Alert threshold percentage" }
            ]},
          { name: "check_frequency", label: "Check Frequency",
            control_type: "select",
            pick_list: [
              ["Every 5 minutes", "5m"],
              ["Every 15 minutes", "15m"],
              ["Every hour", "1h"],
              ["Every day", "24h"]
            ], default: "1h" }
        ]
      end,
      
      webhook_subscribe: lambda do |webhook_url, connection, input|
        call(:validate_table_id, input["table_id"])
        
        response = call(:execute_with_retry, connection, :post, "/api/webhooks",
          payload: {
            url: webhook_url,
            event: "data_table.quality.alert",
            table_id: input["table_id"],
            quality_checks: input["quality_checks"],
            check_frequency: input["check_frequency"]
          })
        response
      end,
      
      webhook_unsubscribe: lambda do |webhook, connection|
        delete("/api/webhooks/#{webhook['id']}")
      end,
      
      webhook_notification: lambda do |input, payload, extended_input_schema, extended_output_schema, headers, params|
        payload
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "table_id", type: "integer" },
          { name: "issues", type: "array", of: "object", properties: [
            { name: "check_type" },
            { name: "column" },
            { name: "issue_count", type: "integer" },
            { name: "percentage", type: "decimal" },
            { name: "threshold_exceeded", type: "boolean" }
          ]},
          { name: "checked_at", type: "timestamp" }
        ]
      end
    },

    table_size_threshold: {
      title: "Table size threshold",
      subtitle: "Triggers when table exceeds size threshold",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer",
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "threshold_type", label: "Threshold Type",
            control_type: "select",
            pick_list: [
              ["Row Count", "rows"],
              ["Storage Size (MB)", "size_mb"],
              ["Growth Rate (%)", "growth_rate"]
            ], optional: false },
          { name: "threshold_value", label: "Threshold Value",
            type: "decimal", optional: false },
          { name: "check_interval", label: "Check Interval",
            control_type: "select",
            pick_list: [
              ["Every Hour", "1h"],
              ["Every 6 Hours", "6h"],
              ["Daily", "24h"]
            ], default: "6h" }
        ]
      end,
      
      poll: lambda do |connection, input, last_poll|
        table_stats = call(:with_rate_limit_retry, connection) do
          get("/api/data_tables/#{input['table_id']}/stats")
        end
        
        threshold_exceeded = case input["threshold_type"]
        when "rows"
          table_stats["row_count"] > input["threshold_value"]
        when "size_mb"
          table_stats["size_mb"] > input["threshold_value"]
        when "growth_rate"
          table_stats["growth_rate_percent"] > input["threshold_value"]
        end
        
        if threshold_exceeded
          {
            events: [{
              table_id: input["table_id"],
              threshold_type: input["threshold_type"],
              threshold_value: input["threshold_value"],
              current_value: table_stats[input["threshold_type"]],
              exceeded_at: Time.now.iso8601
            }],
            next_poll: Time.now
          }
        else
          {
            events: [],
            next_poll: last_poll || Time.now
          }
        end
      end,
      
      dedup: lambda do |event|
        "#{event['table_id']}-#{event['exceeded_at']}"
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "table_id", type: "integer" },
          { name: "threshold_type" },
          { name: "threshold_value", type: "decimal" },
          { name: "current_value", type: "decimal" },
          { name: "exceeded_at", type: "timestamp" }
        ]
      end
    }
  }
}