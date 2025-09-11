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
          ["US (www.workato.com)", "www"],
          ["EU (app.eu.workato.com)", "app.eu"],
          ["JP (app.jp.workato.com)", "app.jp"],
          ["SG (app.sg.workato.com)", "app.sg"],
          ["AU (app.au.workato.com)", "app.au"],
          ["IL (app.il.workato.com)", "app.il"]
        ],
        default: "app.eu",
        optional: false,
        hint: "Select your Workato environment region (default is EU)"
      },
      {
        name: "api_token",
        label: "API Token",
        control_type: "password",
        optional: true,
        hint: "Workspace admin → API clients → API keys (Bearer token)"
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
        ngIf: "input['enable_retry'] == true"
      }
    ],
    
    authorization: {
      type: "custom_auth",
      apply: lambda do |connection|
        headers(
          "Authorization": "Bearer #{connection['api_token']}",
          "Accept": "application/json"
        )
        # Optional but very useful for tracing:
        headers("x-correlation-id": (connection['x_cid'] || SecureRandom.uuid))
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
    me = get("/api/users/me")
    # Only touch data tables if your API client role actually has access:
    begin
      tables = get("/api/data_tables").params(page: 1, per_page: 1)
    rescue RestClient::Forbidden
      tables = { "data" => [] } # valid connection, limited scope
    end

    {
      success: true,
      message: "Connected",
      account_name: me["name"] || me["id"],
      sample_table_count: (tables["data"] || []).length
    }
  rescue RestClient::ExceptionWithResponse => e
    # Bubble up HTTP code + key headers devs need to see
    hdrs = e.response&.headers || {}
    auth_hdr = hdrs["www-authenticate"] || hdrs[:www_authenticate]
    cid = hdrs["x-correlation-id"] || hdrs[:x_correlation_id]
    error("Test failed (#{e.http_code}) auth=#{auth_hdr} cid=#{cid} url=#{e.response&.request&.url}")
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
      max_retries = (connection["max_retries"] || 3).to_i.clamp(0, 6)

      begin
        block.call
      rescue RestClient::ExceptionWithResponse => e
        if e.http_code == 429 && connection["enable_retry"] && retries < max_retries
          hdrs = e.response&.headers || {}
          ra = hdrs["Retry-After"] || hdrs[:retry_after]
          delay =
            if ra.to_s =~ /^\d+$/ then ra.to_i
            elsif ra.present?
              begin
                [(Time.httpdate(ra) - Time.now).ceil, 1].max
              rescue
                60
              end
            else
              60
            end

          # backoff = max(server hint, 2^retries) + jitter(0..3)
          backoff = [delay, (2 ** retries)].max + rand(0..3)
          sleep(backoff)
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
      uuid = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
      error("Table ID must be a UUID") unless table_id.to_s.match?(uuid)
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
        error("Field '#{field_name}' must be an integer") unless value.to_s.match?(/\A-?\d+\z/)
      when "number"
        error("Field '#{field_name}' must be a number") unless value.to_s.match?(/\A-?\d+(\.\d+)?\z/)
      when "boolean"
        unless [true, false, "true", "false", 0, 1, "0", "1"].include?(value)
          error("Field '#{field_name}' must be a boolean")
        end
      when "date_time"
        begin
          DateTime.parse(value.to_s)
        rescue
          error("Field '#{field_name}' must be a valid date_time")
        end
      when "date"
        begin
          Date.parse(value.to_s)
        rescue
          error("Field '#{field_name}' must be a valid date")
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
        all_results.concat(rows)

        has_more = response["has_more"] || (rows.length == params[:limit])
        break unless has_more
        params[:offset] += params[:limit]
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
        if c.key?("case_sensitive") && ["eq", "starts_with"].include?(c["operator"])
          val = { "value" => val, "case_sensitive" => !!c["case_sensitive"] }
        end

        { c["column"] => { oper => val } }
      end.compact

      return nil if conditions.empty?
      if conditions.length == 1 || (filters["operator"] || "and") == "and"
        return conditions.first if conditions.length == 1
        { "$and" => conditions }
      else
        { "$or" => conditions }
      end
    end,

    # Try the canonical records query path, then the legacy one.
    records_query_call: lambda do |connection, table_id, body|
      base = call(:records_base, connection)
      primary  = "#{base}/api/v1/tables/#{table_id}/query"
      fallback = "#{base}/api/v1/tables/#{table_id}/records/query"

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

    # Normalize list endpoints that sometimes return an array at root
    normalize_list_response: lambda do |_connection, resp|
      arr = resp.is_a?(Array) ? resp : (resp["data"] || resp["items"] || [])
      { "data" => arr }
    end,

    # Clamp page/per_page to documented bounds (folders/projects: max 100)
    clamp_pagination: lambda do |_connection, page, per_page, max|
      page = (page || 1).to_i
      per_page = (per_page || 100).to_i
      per_page = 1 if per_page < 1
      per_page = max if per_page > max
      { page: page, per_page: per_page }
    end,

    # Unified GET list call with retry, pagination clamping, and helpful 403 error
    list_index: lambda do |connection, path, params = {}|
      p = call(:clamp_pagination, connection, params[:page], params[:per_page], 100)
      q = params.merge(p).compact
      resp = call(:execute_with_retry, connection) { get(path).params(q) }
      call(:normalize_list_response, connection, resp)
    rescue RestClient::Forbidden => e
      hdrs = e.response&.headers || {}
      cid  = hdrs["x-correlation-id"] || hdrs[:x_correlation_id]
      error("Permission denied for #{path}. Enable API client role privilege: Projects & folders → List folders/projects. cid=#{cid}")
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
    end,
    # ---------- Developer API (tables/folders) ----------
    devapi_create_table: lambda do |connection, input|
      payload = {
        name: input["name"],
        folder_id: input["folder_id"],
        schema: input["schema"]
      }.compact
      call(:execute_with_retry, connection) { post("/api/data_tables").payload(payload) }
    end,

    devapi_update_table: lambda do |connection, input|
      body = {}
      body[:name] = input["name"] if input["name"].present?
      body[:folder_id] = input["folder_id"] if input["folder_id"].present?
      body[:schema] = input["schema"] if input["schema"].present?
      error("Provide at least one field to update") if body.empty?

      path = "/api/data_tables/#{input['table_id']}"
      call(:execute_with_retry, connection) { put(path).payload(body) }
    end,
    
    devapi_truncate_table: lambda do |connection, table_id, confirm|
      error("Truncation not confirmed") unless confirm == true
      path = "/api/data_tables/#{table_id}/truncate"
      call(:execute_with_retry, connection) { post(path) }
      { success: true, truncated_at: Time.now.iso8601 }
    end,

    devapi_move_or_rename_table: lambda do |connection, input|
      body = {}
      body[:name] = input["name"] if input["name"].present?
      body[:folder_id] = input["folder_id"] if input["folder_id"].present?
      error("Provide at least one of name/folder_id") if body.empty?

      path = "/api/data_tables/#{input['table_id']}"
      call(:execute_with_retry, connection) { put(path).payload(body) }
    end,

    devapi_create_folder: lambda do |connection, input|
      payload = { name: input["name"] }
      payload[:parent_id] = input["parent_id"] if input["parent_id"].present?
      resp = call(:execute_with_retry, connection) { post("/api/folders").payload(payload) }
      resp.is_a?(Hash) ? resp : { "id" => resp }
    end,

    devapi_list_folders: lambda do |connection, input|
      params = { page: input["page"], per_page: input["per_page"] }
      params[:parent_id] = input["parent_id"] if input["parent_id"].present?
      call(:list_index, connection, "/api/folders", params)
    rescue RestClient::ExceptionWithResponse => e
      hdrs = e.response&.headers || {}
      cid  = hdrs["x-correlation-id"] || hdrs[:x_correlation_id]
      error("Failed to list folders (#{e.http_code}). cid=#{cid} body=#{e.response&.body}")
    end,

    devapi_list_projects: lambda do |connection, input|
      params = { page: input["page"], per_page: input["per_page"] }
      call(:list_index, connection, "/api/projects", params)
    rescue RestClient::ExceptionWithResponse => e
      hdrs = e.response&.headers || {}
      cid  = hdrs["x-correlation-id"] || hdrs[:x_correlation_id]
      error("Failed to list projects (#{e.http_code}). cid=#{cid} body=#{e.response&.body}")
    end,

    # ---------- Data Tables v1 (records) ----------
    dt_query: lambda do |connection, input|
      call(:validate_table_id, input["table_id"])
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
      resp = call(:records_query_call, connection, input["table_id"], body)
      call(:normalize_records_result, connection, resp)
    end,

    dt_query_next: lambda do |connection, input|
      call(:validate_table_id, input["table_id"])
      body = { continuation_token: input["continuation_token"], limit: input["limit"] }.compact
      resp = call(:records_query_call, connection, input["table_id"], body)
      call(:normalize_records_result, connection, resp)
    end,

    dt_create_record: lambda do |connection, input|
      call(:validate_table_id, input["table_id"])
      base = call(:records_base, connection)
      url  = "#{base}/api/v1/tables/#{input['table_id']}/records"
      result = call(:execute_with_retry, connection) { post(url).payload(input["data"]) }
      rec = result.is_a?(Array) ? (result.first || {}) : result
      { record_id: rec["record_id"], created_at: rec["created_at"], document: rec["document"] }
    end,

    dt_update_record: lambda do |connection, input|
      call(:validate_table_id, input["table_id"])
      base = call(:records_base, connection)
      url  = "#{base}/api/v1/tables/#{input['table_id']}/records/#{input['record_id']}"
      call(:execute_with_retry, connection) { put(url).payload(input["data"]) }
    end,

    dt_delete_record: lambda do |connection, input|
      call(:validate_table_id, input["table_id"])
      base = call(:records_base, connection)
      url  = "#{base}/api/v1/tables/#{input['table_id']}/records/#{input['record_id']}"
      resp = call(:execute_with_retry, connection) { delete(url) }
      status = resp.is_a?(Hash) ? (resp.dig("data","status") || resp["status"]) : nil
      { status: status || 200 }
    end,

    dt_batch_create_records: lambda do |connection, input|
      call(:validate_table_id, input["table_id"])
      base = call(:records_base, connection)
      url  = "#{base}/api/v1/tables/#{input['table_id']}/records"
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
    end,

    dt_batch_update_records: lambda do |connection, input|
      call(:validate_table_id, input["table_id"])
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
    end,

    dt_batch_delete_records: lambda do |connection, input|
      call(:validate_table_id, input["table_id"])
      base = call(:records_base, connection)
      successes = []
      errors = []
      (input["record_ids"] || []).each_with_index do |rid, idx|
        begin
          url = "#{base}/api/v1/tables/#{input['table_id']}/records/#{rid}"
          resp = call(:execute_with_retry, connection) { delete(url) }
          successes << { record_id: rid, status: resp.dig("data","status") || 200 }
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
    end,

    # ----- Pick list helpers -----
    pick_tables: lambda do |connection|
      # Developer API: returns { "data": [ ... ] }
      r = call(:execute_with_retry, connection) do
        get("/api/data_tables").params(page: 1, per_page: 100)
      end
      arr = r.is_a?(Array) ? r : (r["data"] || [])
      arr.map { |t| [t["name"] || t["id"].to_s, t["id"]] }
    rescue RestClient::ExceptionWithResponse => e
      error("Failed to load tables: #{e.response&.body || e.message}")
    end,

    pick_table_columns: lambda do |connection, table_id:|
      return [] unless table_id.present?
      table = call(:execute_with_retry, connection) do
        get("/api/data_tables/#{table_id}")
      end
      cols = table["schema"] || table.dig("data", "schema") || []
      cols.map { |col| [col["name"], col["name"]] }
    rescue RestClient::NotFound
      [] # Table disappeared or ID invalid; return empty so the UI doesn't explode
    rescue RestClient::ExceptionWithResponse => e
      error("Failed to load table columns: #{e.response&.body || e.message}")
    end,

    pick_folders: lambda do |connection|
      # Use list_index for normalization + clamping + retry
      r = call(:list_index, connection, "/api/folders", { page: 1, per_page: 200 })
      (r["data"] || []).map { |f| [f["name"] || f["id"].to_s, f["id"]] }
    end,

    pick_projects: lambda do |connection|
      r = call(:list_index, connection, "/api/projects", { page: 1, per_page: 200 })
      (r["data"] || []).map { |p| [p["name"] || p["id"].to_s, p["id"]] }
    end
  },
  
  # ==========================================
  # PICKUP VALUES (Dynamic field values)
  # ==========================================
  pick_lists: {
    tables: lambda do |connection|
      call(:pick_tables, connection)
    end,
    
    table_columns: lambda do |connection, table_id:|
      call(:pick_table_columns, connection, table_id: table_id)
    end,

    folders: lambda do |connection|
      call(:pick_folders, connection)
    end,

    projects: lambda do |connection|
      call(:pick_projects, connection)
    end
  },

  # ==========================================
  # OBJECT DEFINITIONS
  # ==========================================
  object_definitions: {
  table: {
    fields: lambda do |_connection, _config_fields|
      [
        { name: "id", type: "string", label: "Table ID" }, # UUID string per docs
        { name: "name", label: "Table Name" },
        { name: "description", label: "Description" },
        { name: "schema", type: "array", of: "object", properties: [
          { name: "type" },
          { name: "name" },
          { name: "optional", type: "boolean" },
          { name: "field_id" },
          { name: "hint" },
          { name: "multivalue", type: "boolean" },
          { name: "metadata", type: "object" },
          { name: "relation", type: "object", properties: [
            { name: "table_id" }, { name: "field_id" }
          ] }
        ]},
        { name: "folder_id", type: "integer", label: "Folder ID" },
        { name: "created_at", type: "timestamp", label: "Created At" },
        { name: "updated_at", type: "timestamp", label: "Updated At" }
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
          { name: "is_project", type: "boolean" },
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
          { name: "description" },
          { name: "folder_id" }
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
  # List responses
  # - GET /api/projects → array at root
  # - GET /api/folders → array at root
  # - GET /api/data_tables → envelope { "data": [...] }
  actions: {
    # ---------- TABLES (Developer API) ----------
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
        [
          { name: "data", type: "object", properties: object_definitions["table"] }
        ]
      end,
      execute: lambda do |connection, input|
        call(:devapi_create_table, connection, input)
      end
    },
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
        [
          { name: "data", type: "object", properties: object_definitions["table"] }
        ]
      end,
      execute: lambda do |connection, input|
        call(:devapi_update_table, connection, input)
      end
    }, 
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
      execute: lambda do |connection, input|
        call(:devapi_truncate_table, connection, input["table_id"], input["confirm"])
      end
    },
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
        [
          { name: "data", type: "object", properties: object_definitions["table"] }
        ]
      end,
      execute: lambda do |connection, input|
        call(:devapi_move_or_rename_table, connection, input)
      end
    },

    # ---------- Folders / Projects ----------
    list_folders: {
      title: "List folders",
      input_fields: lambda do
        [
          { name: "parent_id", optional: true, control_type: "select", pick_list: "folders",
            hint: "Defaults to the Home folder when empty" },
          { name: "page", type: "integer", default: 1 },
          { name: "per_page", type: "integer", default: 100 }
        ]
      end,
      output_fields: lambda do |object_definitions|
        [
          { name: "data", type: "array", of: "object", properties: object_definitions["folder"] }
        ]
      end,
      execute: lambda do |connection, input|
        call(:devapi_list_folders, connection, input)
      end
    },
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
      execute: lambda do |connection, input|
        call(:devapi_list_projects, connection, input)
      end
    },
    create_folder: {
      title: "Create folder",
      input_fields: lambda do
        [
          { name: "name", optional: false },
          { name: "parent_id", optional: true, control_type: "select", pick_list: "folders" }
          # Removed project id input field, POST /api/folder does not have project_id param in payload
        ]
      end,
      output_fields: lambda do |_object_definitions|
        [
          { name: "id" }
        ]
      end,
      execute: lambda do |connection, input|
        call(:devapi_create_folder, connection, input)
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
        call(:dt_query, connection, input)
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
        call(:dt_create_record, connection, input)
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
        call(:dt_update_record, connection, input)
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
        call(:dt_delete_record, connection, input)
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
        call(:dt_batch_create_records, connection, input)
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
        call(:dt_batch_update_records, connection, input)
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
        call(:dt_batch_delete_records, connection, input)
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
        call(:dt_query, connection, input)
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
        call(:dt_query_next, connection, input)
      end
    }
    # -- File Column --
    # Generate upload link
    # Attach uploaded file to record
    # Generate download link for file field
    # Download file content (streaming)
  }
}