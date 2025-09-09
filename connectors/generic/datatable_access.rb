{
  title: "Workato Data Tables - Enhanced",
  
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
          ["EU Region", "app.eu"],
          ["JP Region", "app.jp"],
          ["SG Region", "app.sg"]
        ],
        default: "app",
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
        ngIf: "input.auth_type == 'api_token'"
      },
      {
        name: "client_id",
        label: "Client ID",
        control_type: "text",
        optional: true,
        hint: "OAuth Client ID from API Platform settings",
        ngIf: "input.auth_type == 'oauth2'"
      },
      {
        name: "client_secret",
        label: "Client Secret", 
        control_type: "password",
        optional: true,
        hint: "OAuth Client Secret (only shown once when creating API client)",
        ngIf: "input.auth_type == 'oauth2'"
      },
      {
        name: "email",
        label: "Account Email",
        control_type: "text",
        optional: true,
        hint: "Your Workato account email (required for API token auth)",
        ngIf: "input.auth_type == 'api_token'"
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
        ngIf: "input.enable_retry == true"
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
  # ENHANCED TEST CONNECTION
  # ==========================================
  test: lambda do |connection|
    # Test basic connectivity
    user_info = get("/api/user")
    
    # Test data table access
    tables = get("/api/data_tables").params(limit: 1)
    
    # Test permissions
    permissions = get("/api/permissions")
    
    {
      success: true,
      message: "Connection successful!",
      account: user_info["email"],
      workspace: user_info["workspace_name"],
      permissions: permissions["data_tables"],
      tables_accessible: tables["total_count"]
    }
  rescue RestClient::Unauthorized => e
    error("Authentication failed. Please check your credentials.")
  rescue RestClient::Forbidden => e
    error("Access forbidden. Please check your permissions.")
  rescue => e
    error("Connection test failed: #{e.message}")
  end,
  
  # ==========================================
  # HELPER METHODS
  # ==========================================
  methods: {
    # IMPROVEMENT 1: Robust Error Handling
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
    
    # IMPROVEMENT 9: Rate Limiting Handler
    with_rate_limit_retry: lambda do |connection, &block|
      return yield unless connection["enable_retry"]
      
      max_retries = connection["max_retries"] || 3
      retries = 0
      
      begin
        yield
      rescue RestClient::TooManyRequests => e
        if retries < max_retries
          retry_after = e.response.headers[:retry_after].to_i || 60
          sleep(retry_after)
          retries += 1
          retry
        else
          raise
        end
      end
    end,
    
    # IMPROVEMENT 8: Input Validation
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
    
    # IMPROVEMENT 11: Pagination Helper
    paginate_all: lambda do |connection, url, params = {}|
      all_results = []
      params[:limit] ||= 100
      params[:offset] = 0
      
      loop do
        response = get(url).params(params)
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
    end
  },
  
  # ==========================================
  # PICKUP VALUES (Dynamic field values)
  # ==========================================
  pick_lists: {
    tables: lambda do |connection|
      get("/api/data_tables").
        pluck("name", "id").
        map { |name, id| [name, id] }
    end,
    
    table_columns: lambda do |connection, table_id:|
      return [] unless table_id.present?
      
      schema = get("/api/data_tables/#{table_id}/schema")
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
    }
  },
  
  # ==========================================
  # ACTIONS
  # ==========================================
  actions: {
    # ==== TABLE MANAGEMENT ACTIONS ====
    # IMPROVEMENT 2: Create Table
    create_table: {
      title: "Create data table",
      subtitle: "Create a new data table with schema",
      
      input_fields: lambda do
        [
          { name: "name", label: "Table Name", optional: false,
            hint: "Unique name for the data table" },
          { name: "description", label: "Description", optional: true,
            hint: "Description of the table's purpose" },
          { name: "columns", label: "Columns", type: "array", of: "object", 
            optional: false, properties: [
              { name: "name", label: "Column Name", optional: false },
              { name: "type", label: "Data Type", control_type: "select",
                pick_list: [
                  ["String", "string"],
                  ["Integer", "integer"],
                  ["Decimal", "decimal"],
                  ["Boolean", "boolean"],
                  ["Datetime", "datetime"],
                  ["Text", "text"],
                  ["JSON", "json"]
                ],
                optional: false },
              { name: "required", label: "Required", type: "boolean", default: false },
              { name: "unique", label: "Unique", type: "boolean", default: false },
              { name: "default_value", label: "Default Value", optional: true },
              { name: "description", label: "Description", optional: true }
            ]},
          { name: "metadata", label: "Metadata", type: "object", optional: true,
            hint: "Custom metadata for the table" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        object_definitions["table"]
      end,
      
      sample_output: lambda do |connection, input|
        {
          id: 12345,
          name: "customers",
          description: "Customer data table",
          schema_id: 67890,
          row_count: 0,
          created_at: "2024-01-01T10:00:00Z",
          updated_at: "2024-01-01T10:00:00Z",
          created_by: "user@example.com"
        }
      end,
      
      execute: lambda do |connection, input|
        payload = {
          name: input["name"],
          description: input["description"],
          schema: {
            columns: input["columns"]
          }
        }
        payload[:metadata] = input["metadata"] if input["metadata"].present?
        
        call(:with_rate_limit_retry, connection) do
          post("/api/data_tables").payload(payload)
        end
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to create table: #{e.message}")
      end
    },
    
    # IMPROVEMENT 2: Delete Table
    delete_table: {
      title: "Delete data table",
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
        
        call(:with_rate_limit_retry, connection) do
          delete("/api/data_tables/#{input['table_id']}")
        end
        
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
    
    # ==== EXISTING ACTIONS WITH IMPROVEMENTS ====
    list_data_tables: {
      title: "List data tables",
      subtitle: "Get all data tables in your account",
      
      input_fields: lambda do
        [
          { name: "include_metadata", type: "boolean", default: false,
            hint: "Include custom metadata for each table" },
          { name: "include_schema", type: "boolean", default: false,
            hint: "Include schema information for each table" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "tables", type: "array", of: "object", 
            properties: object_definitions["table"] },
          { name: "total_count", type: "integer", label: "Total Count" }
        ]
      end,
      
      sample_output: lambda do |connection, input|
        {
          tables: [
            {
              id: 12345,
              name: "customers",
              schema_id: 67890,
              row_count: 150,
              created_at: "2024-01-01T10:00:00Z",
              updated_at: "2024-01-15T14:30:00Z"
            }
          ],
          total_count: 1
        }
      end,
      
      execute: lambda do |connection, input|
        params = {}
        params[:include_metadata] = true if input["include_metadata"]
        params[:include_schema] = true if input["include_schema"]
        
        call(:with_rate_limit_retry, connection) do
          response = get("/api/data_tables").params(params)
          { 
            tables: response["tables"] || response,
            total_count: response["total_count"] || response.length
          }
        end
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to list tables: #{e.message}")
      end
    },
    
    get_table_schema: {
      title: "Get table schema",
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
        
        call(:with_rate_limit_retry, connection) do
          get("/api/data_tables/#{input['table_id']}/schema")
        end
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to get schema: #{e.message}")
      end
    },
    
    # IMPROVEMENT 3: Advanced Filtering
    search_rows_advanced: {
      title: "Search rows (Advanced)",
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
        
        call(:with_rate_limit_retry, connection) do
          response = get("/api/data_tables/#{input['table_id']}/rows").params(params)
          
          {
            rows: response["rows"],
            total_count: response["total"],
            filtered_count: response["rows"].length,
            has_more: response["has_more"]
          }
        end
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to search rows: #{e.message}")
      end
    },
    
    # IMPROVEMENT 4: Batch Update
    batch_update_rows: {
      title: "Batch update rows",
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
        
        call(:with_rate_limit_retry, connection) do
          response = put("/api/data_tables/#{input['table_id']}/rows/batch").
            payload(payload)
          
          {
            updated_count: response["updated_count"],
            rows: response["rows"],
            errors: response["errors"] || []
          }
        end
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to batch update: #{e.message}")
      end
    },
    
    # IMPROVEMENT 4: Batch Delete
    batch_delete_rows: {
      title: "Batch delete rows",
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
        
        call(:with_rate_limit_retry, connection) do
          response = delete("/api/data_tables/#{input['table_id']}/rows/batch").
            payload(payload)
          
          {
            deleted_count: response["deleted_count"],
            success: response["success"],
            errors: response["errors"] || []
          }
        end
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to batch delete: #{e.message}")
      end
    },
    
    # IMPROVEMENT 6: Export Table
    export_table: {
      title: "Export table data",
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
        
        call(:with_rate_limit_retry, connection) do
          response = post("/api/data_tables/#{input['table_id']}/export").
            payload(payload)
          
          {
            file_url: response["url"],
            file_size: response["size"],
            row_count: response["row_count"],
            expires_at: response["expires_at"]
          }
        end
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to export table: #{e.message}")
      end
    },
    
    # IMPROVEMENT 6: Import Table Data
    import_table_data: {
      title: "Import table data",
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
        
        call(:with_rate_limit_retry, connection) do
          response = post("/api/data_tables/#{input['table_id']}/import").
            payload(payload)
          
          {
            imported_count: response["imported_count"],
            updated_count: response["updated_count"] || 0,
            skipped_count: response["skipped_count"] || 0,
            errors: response["errors"] || []
          }
        end
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to import data: #{e.message}")
      end
    },
    
    # IMPROVEMENT 7: Aggregate Data
    aggregate_data: {
      title: "Aggregate table data",
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
        
        call(:with_rate_limit_retry, connection) do
          response = post("/api/data_tables/#{input['table_id']}/aggregate").
            payload(payload)
          
          {
            results: response["results"],
            row_count: response["row_count"],
            execution_time_ms: response["execution_time_ms"]
          }
        end
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to aggregate data: #{e.message}")
      end
    },
    
    # IMPROVEMENT 12: Add Column
    add_column: {
      title: "Add column to table",
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
        
        call(:with_rate_limit_retry, connection) do
          response = post("/api/data_tables/#{input['table_id']}/columns").
            payload(payload)
          
          {
            success: true,
            column: response
          }
        end
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to add column: #{e.message}")
      end
    },
    
    # IMPROVEMENT 12: Drop Column
    drop_column: {
      title: "Remove column from table",
      subtitle: "Remove a column from an existing table",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", 
            optional: false, control_type: "select", pick_list: "tables" },
          { name: "column_name", label: "Column Name", optional: false,
            control_type: "select", 
            pick_list: "table_columns",
            pick_list_params: { table_id: "table_id" } },
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
        
        call(:with_rate_limit_retry, connection) do
          delete("/api/data_tables/#{input['table_id']}/columns/#{input['column_name']}")
        end
        
        {
          success: true,
          message: "Column '#{input['column_name']}' removed successfully"
        }
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to drop column: #{e.message}")
      end
    },
    
    # Additional: Clone Table
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
        
        call(:with_rate_limit_retry, connection) do
          post("/api/data_tables/#{input['source_table_id']}/clone").
            payload(payload)
        end
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to clone table: #{e.message}")
      end
    },
    
    # Additional: Table Audit Log
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
        
        call(:with_rate_limit_retry, connection) do
          response = get("/api/data_tables/#{input['table_id']}/audit_log").
            params(params)
          
          {
            entries: response["entries"],
            total_count: response["total_count"]
          }
        end
      rescue RestClient::Exception => e
        call(:handle_api_errors, e.response)
        error("Failed to get audit log: #{e.message}")
      end
    }
  },
  
  # ==========================================
  # TRIGGERS
  # ==========================================
  triggers: {
    # IMPROVEMENT 5: Webhook-based triggers
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
        
        payload = {
          url: webhook_url,
          event: "data_table.row.created",
          table_id: input["table_id"]
        }
        payload[:columns] = input["columns"] if input["columns"].present?
        
        post("/api/webhooks").payload(payload)
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
        
        payload = {
          url: webhook_url,
          event: "data_table.row.updated",
          table_id: input["table_id"]
        }
        payload[:columns] = input["columns"] if input["columns"].present?
        
        post("/api/webhooks").payload(payload)
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
        
        post("/api/webhooks").payload(
          url: webhook_url,
          event: "data_table.row.deleted",
          table_id: input["table_id"]
        )
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
        
        post("/api/webhooks").payload(
          url: webhook_url,
          event: "data_table.schema.changed",
          table_id: input["table_id"]
        )
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
    
    # Polling trigger (keeping the original with enhancements)
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
        
        since = last_poll || input["since"] || 1.hour.ago
        
        response = call(:with_rate_limit_retry, connection) do
          get("/api/data_tables/#{input['table_id']}/rows").
            params(
              filter: { created_at: { gt: since } }.to_json,
              sort: "created_at:asc",
              limit: input["batch_size"] || 100
            )
        end
        
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
    }
  }
}