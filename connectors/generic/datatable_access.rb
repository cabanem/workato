{
  title: "Workato Data Tables",
  
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
  
  test: lambda do |connection|
    get("/api/managed_users")
    { success: true, message: "Connection successful!" }
  rescue => e
    error("Connection failed: #{e.message}")
  end,
  
  actions: {
    # List all data tables
    list_data_tables: {
      title: "List data tables",
      subtitle: "Get all data tables in your account",
      
      output_fields: lambda do |object_definitions|
        [
          { name: "tables", type: "array", of: "object", properties: [
            { name: "id", type: "integer" },
            { name: "name" },
            { name: "schema_id", type: "integer" },
            { name: "row_count", type: "integer" },
            { name: "created_at", type: "timestamp" },
            { name: "updated_at", type: "timestamp" }
          ]}
        ]
      end,
      
      execute: lambda do |connection, input|
        response = get("/api/data_tables")
        { tables: response }
      end
    },
    
    # Get data table schema
    get_table_schema: {
      title: "Get table schema",
      subtitle: "Get the schema/structure of a data table",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", optional: false,
            hint: "The ID of the data table" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "id", type: "integer" },
          { name: "name" },
          { name: "columns", type: "array", of: "object", properties: [
            { name: "name" },
            { name: "type" },
            { name: "primary_key", type: "boolean" },
            { name: "required", type: "boolean" }
          ]}
        ]
      end,
      
      execute: lambda do |connection, input|
        get("/api/data_tables/#{input['table_id']}/schema")
      end
    },
    
    # Get rows from a data table
    get_table_rows: {
      title: "Get table rows",
      subtitle: "Retrieve rows from a data table",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", optional: false,
            hint: "The ID of the data table" },
          { name: "limit", type: "integer", default: 100, optional: true,
            hint: "Maximum number of rows to return (default: 100)" },
          { name: "offset", type: "integer", default: 0, optional: true,
            hint: "Number of rows to skip (for pagination)" },
          { name: "filter", type: "object", optional: true,
            hint: "Filter conditions as JSON object" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "rows", type: "array", of: "object" },
          { name: "total_count", type: "integer" },
          { name: "has_more", type: "boolean" }
        ]
      end,
      
      execute: lambda do |connection, input|
        params = {
          limit: input["limit"] || 100,
          offset: input["offset"] || 0
        }
        params[:filter] = input["filter"].to_json if input["filter"].present?
        
        response = get("/api/data_tables/#{input['table_id']}/rows").
          params(params)
        
        {
          rows: response["rows"],
          total_count: response["total"],
          has_more: response["has_more"]
        }
      end
    },
    
    # Insert row into data table
    insert_row: {
      title: "Insert row",
      subtitle: "Add a new row to a data table",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", optional: false,
            hint: "The ID of the data table" },
          { name: "row_data", label: "Row Data", type: "object", optional: false,
            hint: "Data for the new row as key-value pairs" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "id", type: "integer" },
          { name: "created_at", type: "timestamp" },
          { name: "data", type: "object" }
        ]
      end,
      
      execute: lambda do |connection, input|
        response = post("/api/data_tables/#{input['table_id']}/rows").
          payload(input["row_data"])
        
        {
          id: response["id"],
          created_at: response["created_at"],
          data: response
        }
      end
    },
    
    # Update row in data table
    update_row: {
      title: "Update row",
      subtitle: "Update an existing row in a data table",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", optional: false,
            hint: "The ID of the data table" },
          { name: "row_id", label: "Row ID", type: "integer", optional: false,
            hint: "The ID of the row to update" },
          { name: "row_data", label: "Updated Data", type: "object", optional: false,
            hint: "Updated data for the row as key-value pairs" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "id", type: "integer" },
          { name: "updated_at", type: "timestamp" },
          { name: "data", type: "object" }
        ]
      end,
      
      execute: lambda do |connection, input|
        response = put("/api/data_tables/#{input['table_id']}/rows/#{input['row_id']}").
          payload(input["row_data"])
        
        {
          id: response["id"],
          updated_at: response["updated_at"],
          data: response
        }
      end
    },
    
    # Delete row from data table
    delete_row: {
      title: "Delete row",
      subtitle: "Remove a row from a data table",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", optional: false,
            hint: "The ID of the data table" },
          { name: "row_id", label: "Row ID", type: "integer", optional: false,
            hint: "The ID of the row to delete" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "success", type: "boolean" },
          { name: "message" }
        ]
      end,
      
      execute: lambda do |connection, input|
        delete("/api/data_tables/#{input['table_id']}/rows/#{input['row_id']}")
        
        {
          success: true,
          message: "Row deleted successfully"
        }
      end
    },
    
    # Bulk insert rows
    bulk_insert_rows: {
      title: "Bulk insert rows",
      subtitle: "Insert multiple rows at once",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", optional: false,
            hint: "The ID of the data table" },
          { name: "rows", label: "Rows Data", type: "array", of: "object", optional: false,
            hint: "Array of row data objects to insert" }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "inserted_count", type: "integer" },
          { name: "rows", type: "array", of: "object" },
          { name: "errors", type: "array", of: "object" }
        ]
      end,
      
      execute: lambda do |connection, input|
        response = post("/api/data_tables/#{input['table_id']}/rows/bulk").
          payload(rows: input["rows"])
        
        {
          inserted_count: response["inserted_count"],
          rows: response["rows"],
          errors: response["errors"] || []
        }
      end
    },
    
    # Search rows with advanced filtering
    search_rows: {
      title: "Search rows",
      subtitle: "Search for rows with advanced filtering",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", optional: false,
            hint: "The ID of the data table" },
          { name: "search_column", label: "Search Column", optional: true,
            hint: "Column name to search in" },
          { name: "search_value", label: "Search Value", optional: true,
            hint: "Value to search for" },
          { name: "operator", label: "Operator", control_type: "select",
            pick_list: [
              ["Equals", "eq"],
              ["Not Equals", "ne"],
              ["Greater Than", "gt"],
              ["Less Than", "lt"],
              ["Contains", "contains"],
              ["Starts With", "starts_with"],
              ["Ends With", "ends_with"]
            ],
            default: "eq", optional: true },
          { name: "sort_column", label: "Sort By Column", optional: true },
          { name: "sort_order", label: "Sort Order", control_type: "select",
            pick_list: [["Ascending", "asc"], ["Descending", "desc"]],
            default: "asc", optional: true },
          { name: "limit", type: "integer", default: 100, optional: true },
          { name: "offset", type: "integer", default: 0, optional: true }
        ]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "rows", type: "array", of: "object" },
          { name: "total_count", type: "integer" },
          { name: "filtered_count", type: "integer" }
        ]
      end,
      
      execute: lambda do |connection, input|
        params = {
          limit: input["limit"] || 100,
          offset: input["offset"] || 0
        }
        
        # Build filter if search parameters provided
        if input["search_column"].present? && input["search_value"].present?
          filter = {
            input["search_column"] => {
              input["operator"] || "eq" => input["search_value"]
            }
          }
          params[:filter] = filter.to_json
        end
        
        # Add sorting if specified
        if input["sort_column"].present?
          params[:sort] = "#{input['sort_column']}:#{input['sort_order'] || 'asc'}"
        end
        
        response = get("/api/data_tables/#{input['table_id']}/rows").
          params(params)
        
        {
          rows: response["rows"],
          total_count: response["total"],
          filtered_count: response["rows"].length
        }
      end
    }
  },
  
  triggers: {
    # New row trigger (polling-based)
    new_row: {
      title: "New row",
      subtitle: "Triggers when a new row is added to a data table",
      
      input_fields: lambda do
        [
          { name: "table_id", label: "Table ID", type: "integer", optional: false,
            hint: "The ID of the data table to monitor" },
          { name: "since", type: "timestamp", optional: true,
            hint: "Get rows created after this time" }
        ]
      end,
      
      poll: lambda do |connection, input, last_poll|
        since = last_poll || input["since"] || 1.hour.ago
        
        response = get("/api/data_tables/#{input['table_id']}/rows").
          params(
            filter: { created_at: { gt: since } }.to_json,
            sort: "created_at:asc",
            limit: 100
          )
        
        {
          events: response["rows"],
          next_poll: response["rows"].last&.dig("created_at") || since
        }
      end,
      
      dedup: lambda do |row|
        row["id"]
      end,
      
      output_fields: lambda do |object_definitions|
        [
          { name: "id", type: "integer" },
          { name: "created_at", type: "timestamp" },
          { name: "updated_at", type: "timestamp" },
          { name: "data", type: "object" }
        ]
      end
    }
  }
}