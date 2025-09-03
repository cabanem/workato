# frozen_string_literal: true
require 'uri'
require 'json'
require 'date'
require 'base64'
require 'securerandom'
require 'time'
require 'digest'

{
    title: 'Data Utilities',
    subtitle: 'Data Utilities',
    help: ->() {
      "Utility connector for data handling."
    },

    connection: {
      fields: [],
      authorization: { type: 'none' }
    },
  
    test: ->(_connection) {
      { success: true, message: 'Connected successfully.' }
    },

    object_definitions: {
        transformed_output: {
            fields: ->(object_definitions, _connection, _config_fields) {
                [
                    {
                        control_type: 'nested_fields',
                        type: 'array',
                        of: 'object',
                        name: 'date_entries',
                        label: 'Date Entries',
                        optional: true,
                        hint: 'Array of {date, units, status}',
                        sticky: true,
                        properties: object_definitions['date_entry_fields']
                    }
                ]
            }
        },
        date_entry_fields: {
            fields: ->(_connection, _config_fields) {
                [
                    { control_type: 'date',   label: 'Date',  name: 'date',  type: 'date',   optional: false, sticky: true, hint: 'YYYY-MM-DD' },
                    { control_type: 'number', label: 'Units', name: 'units', type: 'number', optional: true, sticky: true, parse_output: 'float_conversion', hint: '0.1–10; days or hours' },
                    { control_type: 'text',   label: 'Status',name: 'status',type: 'string', optional: true, sticky: true, hint: 'Approval response text' }
                ]
            }
        },
        date_entries: {
          fields: ->(object_definitions, _connection, _config_fields) {
            [
              {
                control_type: 'nested_fields',
                type: 'array',
                of: 'object',
                name: 'date_entries',
                label: 'Date Entries',
                hint: 'Add entries or map an array pill here',
                properties: object_definitions['date_entry_fields']
              }
            ]
          }
        },
        date_entry: {
            fields: ->(_connection, _config_fields) {
                [
                    { name: 'date',  label: 'Date',  type: 'date',    optional: true, sticky: true, convert_input: 'date_conversion', convert_output: 'date_conversion' },
                    { name: 'units', label: 'Units', type: 'number',  hint: 'E.g. 1, 0.5, 2, etc.', optional: true, sticky: true },
                    { name: 'status', label: 'Status', type: 'string', optional: true, sticky: true }
                ]
            }
        },
        date_generic: {
          fields: ->(_connection, _config_fields) {
            [
              { control_type: 'date', label: 'Date', name: 'date', type: 'date', optional: false, sticky: true, convert_input: 'date_conversion' }
            ]
          }
        },
        # Input record schema: add entries as required
        input_record: {
            fields: ->(object_definitions, _connection, _config_fields) {
                [
                    {
                        control_type: 'nested_fields',   # adds "Add date entry"
                        type: 'array',
                        of: 'object',
                        name: 'date_entries',
                        label: 'Date Entries',
                        optional: true,
                        hint: 'Add one entry per requested date',
                        properties: object_definitions['date_entry_fields']
                    }
                ]
            }
        },
        # Field Discovery Definitions
        field_discovery: {
          fields: ->(_connection, _config_fields) {
            [
                { name: 'available_fields', label: 'Field Names', type: 'array', of: 'string', hint: 'List of field names' },
                { name: 'field_labels',     label: 'Field Labels',     type: 'object',          hint: 'Map of field to human-readable label' }
            ]
          }
        },
        generic_input: {
            fields: ->(_connection, _config_fields) {
                [
                    {
                        name: "records",
                        label: "Records",
                        type: "array",
                        of: "object",
                        optional: true,
                        hint: 'Input array of objects to process',
                        properties: []
                    }
                ]
            }
        },
        generic_output: {
          fields: ->(_connection, _config_fields) {
            [
                { name: 'records',        label: 'Records',         type: 'array',   of: 'object', hint: 'Filtered record set' },
                { name: 'filtered_count', label: 'Filtered Count',  type: 'integer', optional: true, hint: 'Number of records after filter' },
                { name: 'original_count', label: 'Original Count',  type: 'integer', optional: true, hint: 'Number of records before filter' },
                { name: 'error',          label: 'Error',           type: 'string',  optional: true, hint: 'Error message if any' }
            ]
          }
        },
        filter_input: {
            fields: ->(_connection, _config_fields) {
                [
                    { 
                        name: "records",
                        label: "Records", 
                        type: "array", 
                        of: "object",
                        properties: [
                            {
                                name: "record_type",
                                label: "Record Type",
                                type: :string,
                                optional: false
                            },
                            {
                                name: "request_date",
                                label: "Request Date",
                                type: "date_time",
                                optional: false
                            },
                            {
                                name: "approver_email",
                                label: "Approver Email",
                                type: "string",
                                optional: false
                            },
                        ]
                    }
                ]
            }
        },
        filter_output: {
            fields: ->(_connection, _config_fields) {
                [
                    { name: "records", label: "Records", type: "array", of: "object" },
                    { name: "error", label: "Error", type: "string", optional: true }
                ]
            }
        },
        approver_response_object: {
          fields: -> {
            # Define fields
            (1..10).map do |i|
                {
                    name: "approval#{i}",
                    label: "Approval #{i}",
                    type: 'string',
                    optional: true,
                    control_type: 'text',
                    hint: 'Approval status (e.g., Approve/Reject) for approver ' + i.to_s
                }
            end
          }
        },
        approval_result_output: {
            fields: -> {
                [
                    {
                        name: 'result',
                        type: 'string',
                        optional: true,
                        label: 'Approval Status',
                        control_type: 'text',
                        hint: 'Overall status: Approve, Reject, Partial approval, or empty if none.'
                    }
                ]
            }
        },
        url_input: {
            fields: ->(connection, config_fields) {
                [
                    {
                        name: 'employee_name',
                        type: :string,
                        label: 'Employee Name',
                        optional: false, 
                        control_type: 'text',
                        hint: 'Name of the employee requesting the holiday'
                    },
                  {
                        name: 'approver_email',
                        type: :string,
                        label: 'Approver Email',
                        optional: false, 
                        control_type: 'text',
                        hint: 'Email (or equivalent identifier) of the approver.'
                    },
                    {
                        name: 'portal_record_id',
                        type: :string,
                        label: 'Record ID (request)',
                        optional: false, 
                        control_type: 'text',
                        hint: 'Record ID of the original request'
                    },
                    {
                        name: 'num_days_requested',
                        type: :integer,
                        label: 'Number of Days Requested',
                        optional: false, 
                        control_type: 'integer',
                        hint: 'Number of days requested by the employee'
                    },
                    {
                        name: 'base_url',
                        type: :string,
                        label: 'Base url',
                        optional: false, 
                        control_type: 'text',
                        hint: 'The base URL of the public form'
                    },
                    {
                        name: 'date_entries',
                        type: :array,
                        of: :object,
                        label: 'Date Entries',
                        optional: false, 
                        initially_expanded: true,
                        properties: [
                            {
                                name: 'units',
                                type: :number,
                                label: 'Units',
                                optional: true, 
                                control_type: 'number',
                                sticky: true
                            },
                            {
                                name: 'date',
                                type: :date,
                                label: 'Date',
                                optional: true, 
                                convert_input: 'date_conversion',
                                convert_output: 'date_conversion',
                                sticky: true
                            }
                        ]
                    }
                ]
            }
        },
        url_output: {
            fields: ->(connection, config_fields) {
                [ 
                    { name: 'approver_link', type: :string, label: 'Approver Link' },
                    { name: 'error_msg_link', type: :string, control_type: 'text', label: 'Error Message (URL)' },
                    { name: 'stacktrace', type: :array, of: :string, label: 'Stack Trace'}
                ]
            }
        },
        table_input: {
            fields: ->(object_definitions, connection, config_fields) {
                [
                    {
                        name: 'date_entries',
                        type: :array,
                        of: :object,
                        control_type: 'nested_fields',
                        label: 'Date Entries',
                        optional: false,
                        initially_expanded: true,
                        sticky: true,
                        hint: 'Each entry needs date and units; status is optional.',
                        properties: object_definitions['date_entry_fields']
                     }
                    }
                ]
            }
        },
        table_output: {
            fields: ->(connection, config_fields) {
                [ 
                    { name: 'html_table', type: :string, label: 'HTML Table', control_type: 'text-area', content_type: 'text/html' },
                    { name: 'error_msg_generate_table', type: :string, control_type: 'text', label: 'Error Message (Table)' }
                ]
            }
        },
        email_input_rfc822: {
            fields: -> (object_definitions, _connection) {
                [
                    {
                        name: 'sender_details',
                        type: :object,
                        control_type: 'form',
                        label: 'Sender Details',
                        properties: [
                            {
                                name: 'from',
                                type: 'string',
                                control_type: 'text',
                                label: 'From',
                                hint: 'Sender email address. E.g., "Sender Name <sender@example.com>" or just sender@example.com.',
                                optional: false
                            }
                        ]
                    },
                    {
                        name: 'recipient_details',
                        type: :object,
                        control_type: 'form',
                        label: 'Recipient Details',
                        properties: [
                        {
                            name: 'to',
                            type: 'array',
                            of: 'string',
                            control_type: 'text',
                            label: 'To',
                            hint: 'Recipient email address(es). Use a list pill or comma-separated values.',
                            optional: false
                        },
                        {
                            name: 'cc',
                            type: 'array',
                            of: 'string',
                            control_type: 'text',
                            label: 'Cc',
                            optional: true,
                            hint: 'CC recipient email address(es).'
                        },
                        {
                            name: 'bcc',
                            type: 'array',
                            of: 'string',
                            control_type: 'text',
                            label: 'Bcc',
                            optional: true,
                            hint: 'BCC recipient email address(es).'
                        },
                        {
                            name: 'reply_to',
                            type: 'array',
                            of: 'string',
                            control_type: 'text',
                            label: 'Reply-To',
                            optional: true,
                            hint: 'Reply-To email address(es).'
                        }
                        ]
                    },
                    {
                        name: 'email_content',
                        type: :object,
                        control_type: 'form',
                        label: 'Email Content',
                        properties: [
                        {
                            name: 'subject',
                            type: 'string',
                            control_type: 'text',
                            label: 'Subject',
                            optional: false
                        },
                        {
                            name: 'text_body',
                            type: 'string',
                            control_type: 'text-area',
                            label: 'Text Body',
                            optional: true,
                            hint: 'Plain text version of the email body.'
                        },
                        {
                            name: 'html_body',
                            type: 'string',
                            control_type: 'text-area',
                            label: 'HTML Body',
                            optional: true,
                            hint: 'HTML version of the email body.'
                        }
                        ]
                    },
                    {
                        name: 'attachments',
                        label: 'Attachments',
                        type: :array,
                        of: :object,
                        control_type: 'nested_fields',
                        initially_expanded: false,
                        optional: true,
                        hint: 'Add one object per file. Prefer passing base64 content for binary files.',
                        properties: [
                        { name: 'filename',        type: 'string', control_type: 'text',       label: 'Filename',         optional: false, hint: 'e.g., report.pdf' },
                        { name: 'mime_type',       type: 'string', control_type: 'text',       label: 'MIME Type',        optional: true,  hint: 'Optional. Auto-detected from filename if omitted.' },
                        { name: 'content_base64',  type: 'string', control_type: 'text-area',  label: 'Content (Base64)', optional: true,  hint: 'Base64-encoded file content (recommended).' },
                        { name: 'content',         type: 'string', control_type: 'text-area',  label: 'Content (Raw)',    optional: true,  hint: 'Raw text content for small text files. Ignored if Base64 is present.' },
                        { name: 'disposition',     type: 'string', control_type: 'text',       label: 'Disposition',      optional: true,  hint: 'attachment (default) or inline' },
                        { name: 'content_id',      type: 'string', control_type: 'text',       label: 'Content-ID',       optional: true,  hint: 'If disposition=inline, reference as cid:VALUE inside HTML.' }
                        ]
                    }
                ]
            }
        },
        email_output_rfc822: {
          fields: -> (object_definitions, _connection) {
            [
              { 
                      name: 'raw',
                      type: 'string', 
                      label: 'Raw Message',
                      hint: 'Base64 URL-safe encoded RFC 822 email message, suitable for use with email APIs like Gmail.' 
              }
            ]
          }
        },
        email_input: {
            fields: ->(connection) {
                [
                    {
                        name: 'email_content',
                        type: :object,
                        control_type: 'form',
                        label: 'Email Content',
                        optional: false,
                        properties: [
                            { 
                                name: 'email_type',
                                type: :string,
                                control_type: 'select',
                                label: 'Email Type',
                                optional: true, sticky: true,
                                group: 'Email Content',
                                pick_list: 'email_types_general',
                                toggle_hint: "Select from list",
                                toggle_field: {
                                    name: "email_type",
                                    label: "Email Type",
                                    type: :string,
                                    control_type: "text",
                                    optional: true,
                                    toggle_hint: "Enter custom text"
                                }
                            },
                            { 
                                name: 'custom_greeting',
                                type: :string,
                                control_type: 'select',
                                label: 'Custom Greeting',
                                optional: true,
                                sticky: true,
                                group: 'Email Content',
                                pick_list: 'email_greeting',
                                toggle_hint: "Select from list",
                                toggle_field: {
                                    name: "custom_greeting",
                                    label: "Custom Greeting",
                                    type: :string,
                                    control_type: "text",
                                    optional: true,
                                    toggle_hint: "Enter custom text"
                                }
                            },
                            { 
                                name: 'custom_body', 
                                type: :string,
                                control_type: 'text-area',
                                label: 'Custom Message Body',
                                optional: false, 
                                sticky: true, 
                                group: 'Email Content' 
                            },
                            { 
                                name: 'custom_signoff', 
                                type: :string, 
                                control_type: 'select', 
                                label: 'Custom Signoff', 
                                optional: true, 
                                sticky: true, 
                                group: 'Email Content',
                                pick_list: 'email_signoff',
                                toggle_hint: "Select from list",
                                toggle_field: {
                                    name: "custom_signoff",
                                    label: "Custom Signoff",
                                    type: :string,
                                    control_type: "text",
                                    optional: true,
                                    toggle_hint: "Enter custom text"
                                }
                            },
                            { 
                                name: 'custom_sender_name',
                                type: :string,
                                control_type: 'select',
                                label: 'Custom Sender Name', 
                                optional: true, 
                                sticky: true, 
                                group: 'Email Content',
                                pick_list: 'email_sender_name',
                                toggle_hint: "Select from list",
                                toggle_field: {
                                    name: "custom_sender_name",
                                    label: "Custom Sender Name",
                                    type: :string,
                                    control_type: "text",
                                    optional: true,
                                    toggle_hint: "Enter custom text"
                                }
                            },
                        ],
                        sticky: true
                    }
                ]
            }
        },
        email_input_additional: {
            fields: ->(connection) {
                [
                  {
                    name: 'additional_content',
                    type: :object,
                    control_type: 'form',
                    label: 'Additional Content',
                    optional: true,
                    sticky: true,
                    properties: [
                        { name: 'html_table', type: :string, control_type: 'text-area', label: 'Predefined HTML Table', optional: true, hint: 'Pass in table HTML', sticky: true },
                        { name: 'approver_link', type: :string, control_type: 'text-area', label: 'Predefined Approver Link', optional: true, hint: 'Pass in encoded link', sticky: true }
                    ]
                  }
                ]
            }
        },
        email_input_custom_fields: {
            fields: ->(_connection) {
                [
                    name: 'email_content',
                    type: :object,
                    control_type: 'form',
                    label: 'Email Content',
                    optional: false,
                    properties: [
                        { name: 'custom_greeting',      type: :string, control_type: 'select',      label: 'Custom Greeting',       optional: true,     sticky: true, group: 'Email Content' },
                        { name: 'custom_body',          type: :string, control_type: 'text-area',   label: 'Custom Message Body',   optional: false,    sticky: true, group: 'Email Content' },
                        { name: 'custom_signoff',       type: :string, control_type: 'select',      label: 'Custom Signoff',        optional: true,     sticky: true, group: 'Email Content' },
                        { name: 'custom_sender_name',   type: :string, control_type: 'select',      label: 'Custom Sender Name',    optional: true,     sticky: true, group: 'Email Content' }
                    ]
                ]
            }
        },
        email_output: {
            fields: ->(connection, config_fields) {
                [
                    { name: 'html_body',  type: :string, label: 'HTML Body', control_type: 'text-area', content_type: 'text/html' },
                    { name: 'error_msg_generate_email', type: :string, control_type: 'text', label: 'Error Message (Email)' }
                ]
            }
        },
        error_input: {
            fields: ->(connection) {
                [
                    {
                        name: 'error_details',
                        type: :object,
                        control_type: 'form',
                        label: 'Error Details',
                        optional: false,
                        properties: [
                            { control_type: 'text', label: 'Error Type', name: 'error_type', type: 'string', optional: true, sticky: true, group: 'Error Details' },
                            { control_type: 'text', label: 'Error Message', name: 'error_msg', type: 'string', optional: true, sticky: true, group: 'Error Details' },
                            { 
                                control_type: 'date_time', label: 'Error Time', name: 'error_time', type: 'date_time', optional: true, sticky: true,
                                render_input: 'date_time_conversion', parse_output: 'date_time_conversion', group: 'Error Details' 
                            },
                            { control_type: 'text', label: 'Error Line', name: 'error_line', type: 'string', optional: true, sticky: true, group: 'Error Details' },
                            { control_type: 'text', label: 'Error Action', name: 'error_action', type: 'string', optional: true, sticky: true, group: 'Error Details' },
                            { 
                                name: 'error_link',
                                label: 'Link to Error Details',
                                type: :string, 
                                control_type: 'url',
                               optional: true,
                                sticky: true 
                            }
                        ]
                    }
                ]
            }
        },
        date_label_table: {
          fields: ->(connection, config_fields, object_definitions) {
            [
              { name: 'Created time', type: :date, control_type: 'date', convert_input: "date_conversion", convert_output: "date_conversion", optional: true, sticky: true },
              { name: 'Last modified time', type: :date, control_type: 'date', convert_input: "date_conversion", convert_output: "date_conversion", optional: true, sticky: true },
              { name: 'Last get', type: :date, control_type: 'date', convert_input: "date_conversion", convert_output: "date_conversion", optional: true, sticky: true}
            ]
          }
        }
    },

    pick_lists: {
        num_opts_thru_10: -> {
            (1..10).map { |i| [i, i] }
        },
        num_opts_thru_31: -> {
            (1..31).map { |i| [i, i] }
        },
        num_opts_thru_7: -> {
            (1..7).map { |i| [i, i] }
        },
        record_fields: ->(config_fields) {
            if config_fields['sample_record'].present?
                record = config_fields['sample_record']
                record = JSON.parse(record) if record.is_a?(String)
                record.keys
                  .map { |k| [k.split('_').map(&:capitalize).join(' '), k] }
                  .sort_by(&:first)
            else
                [
                    ['Created time', 'created_time'],
                    ['Last modified time', 'last_modified_time'],
                    ['Last get', 'last_get'],
                    ['Last verified', 'last_verified']
                ]
            end
        },
        email_types_general: -> {
            [
                ['Link and table', 'table_link'],
                ['Link only', 'link'],
                ['Table only', 'table'],
                ['Message only', 'body']
            ]
        },
        email_purpose: -> {
          [
            [ 'Error Notification', 'Error Notification' ],
            [ 'Application', 'Application' ]
          ]
        },
        email_subject: -> {
          [
            [ 'Holiday Request - Rejected', 'Holiday Request - Rejected' ],
            [ 'New Worker Holiday Request - Action Needed', 'New Worker Holiday Request - Action Needed' ],
            [ 'Response Needed - Worker Holiday Request', 'Response Needed - Worker Holiday Request' ],
            [ 'Holiday Request Received', 'Holiday Request Received' ],
            [ 'Duplicate Response Received for Holiday Request', 'Duplicate Response Received for Holiday Request' ],
            [ 'Your Holiday Request is Complete', 'Your Holiday Request is Complete' ],
            [ 'Response Received', 'Response Received' ],
            [ 'Expired Holiday Request', 'Expired Holiday Request' ],
            [ 'Error Notification - Holiday Request Process', 'Error Notification - Holiday Request Process' ]
          ]
        },
        email_signoff: -> {
          [
            [ 'Thank you!', 'Thank you!' ],
            [ 'Kind regards,', 'Kind regards,' ],
            [ 'Best regards', 'Best regards' ]
          ]
        },
        email_sender_name: -> {
            [ 'REDACTED Contractor Care Team', 'REDACTED Contractor Care Team' ]
        },
        email_greeting: -> {
            [ 'Hello,', 'Hello' ]
        },
        public_form_base_url: -> {
          [
            [ 'Holiday Approval Form URL', 'public/pages/9ZQNksYrBScDYJbpEGuT1J/' ],
            [ 'Public Expiry URL', 'public/pages/W7xPFfudQvrFCPt2vjwrH/' ]
          ]
        },
        table_classes: -> {
            [
                ["Default data table", "data-table"],
                ["Striped rows", "table-striped"],
                ["Bordered cells", "table-bordered"],
                ["Highlight on hover", "table-hover"],
                ["Compact spacing", "table-condensed"],
                ["Mobile responsive", "table-responsive"],
                ["Dark theme", "custom-table-dark"],
                ["Light theme", "custom-table-light"]
            ]
        },
        empty_field_handling_options: -> {
            [
                [ 'Preserve Empty Values', 'preserve' ],
                [ 'Convert Empty to Null', 'to_null' ],
                [ 'Convert Null to Empty String', 'to_empty' ],
                [ 'Omit Empty/Null Fields', 'omit' ]
            ]
        },
        output_format_options: -> {
          [
            ['Nested Array (Standard)', 'nested_array'],
            ['Flat Fields (e.g., entry_1_date, entry_2_date)', 'flat_fields'],
            ['Lists (e.g., dates[], units[])', 'lists'],
            ['Both Nested and Flat', 'both']
          ]
        }
    },
  
    triggers: {
        discover_fields: {
            title: 'Discover JSON Keys',
            input_fields: ->(object_definitions, connection, config_fields) {
                [{
                    name: 'sample_records',
                    label: 'Sample Records',
                    type: :array,
                    of: :object,
                    control_type: 'text-area',
                    optional: false
                }]
            },
            webhook_subscribe:      ->(_connection, _input_fields, _flow_id) { { webhook_id: 'discover' } },
            webhook_unsubscribe:    ->(_connection, _id) {},
            dedup:                  ->(records) { Digest::SHA1.hexdigest(record.to_json) },
            webhook_notification:   ->(input, _payload) {
                records = input['sample_records'] || []
                first   = records.first || {}
                keys    = first.keys.map(&:to_s)
                labels  = keys.each_with_object({}) do |k,h|
                    h[k] = k.split('_').map(&:capitalize).join(' ')
                end
                {available_fields: keys, field_labels: labels }
            },
            output_fields: ->(object_definitions, _connection, _config_fields) {
                object_definitions['field_discovery']
            }
        }
    },
    actions: {
        # Data Transformation
        transform_fields_to_json: {
            title: "Serialize Fields to JSON ++",
            subtitle: "Transform 2D data into structured format with flexible output options",
            display_priority: 9,
            help: ->() {
                "This action transforms a wide-form data table (with fields like entry_1_date, entry_1_units, etc.) " +
                "into a structured format. It outputs the data as a serialized JSON string and provides flexible " +
                "structured outputs including a nested array of date entries, flat fields (e.g., entry_1_date, entry_2_date), " +
                "or separate lists of dates, units, and statuses, based on the configured Output Format."
            },
            config_fields: [
                {
                    name: 'num_entries',
                    type: :integer,
                    label: 'Number of Date Entries',
                    control_type: 'select',
                    pick_list: 'num_opts_thru_10',
                    hint: 'Select the maximum number of date entries',
                    optional: false,
                    toggle_hint: 'Select from list',
                    toggle_field: {
                        name: 'num_entries',
                        label: 'Custom Number of Date Entries',
                        type: :integer,
                        control_type: 'number',
                        optional: false,
                        toggle_hint: 'Enter custom value'
                    }
                },
                {
                    name: 'output_format',
                    label: 'Output Format',
                    type: :string,
                    control_type: 'select',
                    pick_list: 'output_format_options',
                    optional: false,
                    default: 'both',
                    hint: 'Choose how you want the data structured in the output',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                        name: 'output_format',
                        label: 'Custom Output Format',
                        type: :string,
                        control_type: 'text',
                        optional: false,
                        toggle_hint: 'Enter custom value',
                        hint: 'Valid values: nested_array, flat_fields, lists, both'
                    }
                },
                {
                    name: 'max_flat_entries',
                    label: 'Maximum Flat Fields',
                    type: :integer,
                    control_type: 'select',
                    pick_list: 'num_opts_thru_31',
                    optional: true,
                    default: 10,
                    hint: 'Maximum number of entries to expose as individual flat fields (if flat format chosen)',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                        name: 'max_flat_entries',
                        label: 'Custom Maximum Flat Fields',
                        type: :integer,
                        control_type: 'number',
                        optional: true,
                        toggle_hint: 'Enter custom value'
                    }
                }
            ],
            input_fields: ->(object_definitions, connection, config_fields) {
                max = (config_fields['num_entries'] || 1).to_i
                entry_props = object_definitions['date_entry_fields']

                # Build one form per entry
                (1..max).map do |i|
                    {
                        name: "entry_#{i}",
                        label: "Entry #{i}",
                        type: 'object',
                        control_type: 'form',
                        properties:   entry_props,
                        optional: true,
                        sticky: true
                    }
                end
            },
            output_fields: ->(object_definitions, _connection, config_fields) {
                format = (config_fields['output_format'] || 'both').to_s
                max    = (config_fields['max_flat_entries'] || 10).to_i
                [ 
                    { control_type: 'text', type: 'string', name: 'serialized_entries', label: 'Serialized Entries JSON' },
                    *call(:output_fields_for_format, object_definitions, format, max),
                    { name: 'total_requested_units', label: 'Total Requested Units', type: 'number', optional: true, hint: 'Sum of all valid units requested' }
                ]
            },
            execute: ->(_connection, input) {
                num     = (input['num_entries'] || 0).to_i
                format  = (input['output_format'] || 'both').to_s
                max     = (input['max_flat_entries'] || 10).to_i

                # 1) Build the array
                raw = call(:build_entries, input, num)

                # 2) Normalize (lenient)
                entries = call(:normalize_entries, raw, strict: false)

                # 3) Serialize the array into JSON
                total = entries.sum { |e| e['units'] || 0.0 }
                serialized = call(:serialize_entries, entries)

                # 4) Prepare the output hash
                out = { 'serialized_entries' => serialized, 'total_requested_units' => total }

                if %w[nested_array both].include?(format)
                    out['date_entries'] = entries
                end
                if %w[lists both].include?(format)
                    out['dates']    = entries.map { |e| e['date'] }
                    out['units']    = entries.map { |e| e['units'] }
                    out['statuses'] = entries.map { |e| e['status'] }.compact
                end
                if %w[flat_fields both].include?(format)
                    entries.first(max).each_with_index do |entry, idx|
                        i = idx + 1
                        out["entry_#{i}_date"]   = entry['date']
                        out["entry_#{i}_units"]  = entry['units']
                        out["entry_#{i}_status"] = entry['status'] if entry['status']
                    end
                end

                out
            }
        },
        transform_flatten_json_date_entries: {
            title: "Deserialize JSON (Date Entries)",
            subtitle: "Parse a JSON string into a nested date_entries array",
            display_priority: 9,
            config_fields: [
                {
                    name: 'output_format',
                    label: 'Output Format',
                    type: :string,
                    control_type: 'select',
                    pick_list: 'output_format_options',
                    optional: false,
                    default: 'both',
                    hint: 'Choose how you want the data structured in the output',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                        name: 'output_format',
                        label: 'Custom Output Format',
                        type: :string,
                        control_type: 'text',
                        optional: false,
                        toggle_hint: 'Enter custom value',
                        hint: 'Valid values: nested_array, flat_fields, lists, both'
                    }
                },
                {
                    name: 'max_flat_entries',
                    label: 'Maximum Flat Fields',
                    type: :integer,
                    control_type: 'select',
                    pick_list: 'num_opts_thru_31',
                    optional: true,
                    default: 10,
                    hint: 'Maximum number of entries to expose as individual fields (if flat format chosen)',
                    toggle_hint: 'Select from list',
                    toggle_field: {
                        name: 'max_flat_entries',
                        label: 'Custom Maximum Flat Fields',
                        type: :integer,
                        control_type: 'number',
                        optional: true,
                        toggle_hint: 'Enter custom value'
                    }
                }
            ],
            input_fields: ->(_object_definitions, _connection, _config_fields) {
                [
                    {
                        name: 'serialized_entries',
                        label: 'Serialized Entries JSON',
                        type: 'string',
                        control_type: 'text',
                        optional: false,
                        hint: 'JSON string containing date entries'
                    }
                ]
            },
            output_fields: ->(object_definitions, _connection, config_fields) {
                format = (config_fields['output_format'] || 'both').to_s
                max    = (config_fields['max_flat_entries'] || 10).to_i
                call(:output_fields_for_format, object_definitions, format, max)
            },
            execute: ->(_connection, input) {
                format  = (input['output_format'] || 'both').to_s
                max     = (input['max_flat_entries'] || 10).to_i
                raw     = input['serialized_entries']
              
                # 1) Normalize into array of hashes
                parsed = case raw
                when String
                    begin
                        JSON.parse(raw)
                    rescue JSON::ParserError => e
                        raise "Invalid JSON for date entries: #{e.message}"
                    end
                when Array then raw
                else
                    raise "Expected String or Array for serialized_entries, got #{raw.class}"
                end

                # 2) Convert types (Str->Date, Str/Num->Float)
                entries = call(:normalize_entries, parsed, strict: true)

                out = {}
                if %w[nested_array both].include?(format)
                    out['date_entries'] = entries
                end
                if %w[lists both].include?(format)
                    out['dates']    = entries.map { |e| e['date'] }
                    out['units']    = entires.map { |e| e['units'] }
                    out['statuses'] = entries.map { |e| e['status'] }
                end
                if %w[flat_fields both].include?(format)
                    entries.first(max).each_with_index do |entry, idx|
                        i = idx + 1
                        out["entry_#{i}_date"]      = entry['date']
                        out["entry_#{i}_units"]     = entry['units']
                        out["entry_#{i}_status"]    = entry['status']
                    end
                end
                out
            }
        },
        # Filtering
        validate_record_freshness: {
          title: "Validate Record Age",
          subtitle: "Validate the age of a record based on specific fields",
          display_priority: 9,
          help: "This action iterates through a list of records and checks a specified date field. " +
                  "It returns true if any record is older than the configured freshness period, or if the date field is missing or invalid.",
          
          config_fields: [
            {
              name: 'freshness_days',
              label: 'Freshness Period (days)',
              type: :integer,
              control_type: 'number',
              optional: false,
              default: 180,
              hint: 'A record is considered "expired" if its last verified date is older than this many days.'
            },
            {
              name: 'sample_record',
              label: 'Sample Records',
              type: :object,
              control_type: 'json-editor',
              optional: true,
              hint: 'Provide a sample JSON object.'
            },
            {
              name: 'date_field_name',
              label: 'Date Field Name',
              type: :string,
              control_type: 'select',
              pick_list: 'record_fields',
              optional: false,
              default: 'last_verified',
              hint: 'The API name of the date field to check in each record.'
            }
          ],
          input_fields: ->(_connection, object_definitions) {
            object_definitions['generic_input']
          },
          output_fields: ->(_object_definitions) {
            [
              { name: 'is_expired', type: :boolean, label: 'Expired Record Found', hint: 'True if at least one expired or invalid record was found.' },
              { name: 'status', type: :string, label: 'Status', hint: 'Indicates if the operation was successful or encountered an error.' },
              { name: 'message', type: :string, label: 'Message', hint: 'A descriptive message about the validation result.' }
            ]
          },
          execute: ->(_connection, input) {
            # 1. Get input and configuration
            records        = input['records']
            freshness_days = (input['freshness_days'] || 180).to_i
            date_field     = input['date_field_name'] || 'last_verified'
             
            
            # 2. Validate that records is an array
            unless records.is_a?(Array)
              return {
                "is_expired" => true,
                "status" => "error",
                "message" => "Input 'records' was not an array. Received #{records.class}."
              }
            end
            
            # 3. Calculate expiration threshold
            expiration_threshold = Time.now.utc - (freshness_days * 24 * 60 * 60)
            
            # 4. Use 'any?' to find first expired record (early exit)
            any_expired = records.any? do |record|
              call(:is_record_expired?, record, date_field, expiration_threshold)
            end
            
            # Return result
            if any_expired
              {
                "is_expired" => true,
                "status" => "success",
                "message" => "Expired or invalid record found."
              }
            else
              {
                "is_expired" => false,
                "status" => "success",
                "message" => "No expired or invalid entries found."
              }
            end
          }
        },
        # Holiday requests
        filter_time_records: {
            title: "Holiday Requests - Filter Records in a Time Series",
            subtitle: "Filter records based on time thresholds",
            display_priority: 0,
            deprecated: true,
            help: ->() {
              "Use this calculate time."
            },
            input_fields: ->(object_definitions) {
                object_definitions['generic_input']
            },
            output_fields: ->(object_definitions) {
                object_definitions['generic_output']
            },
            config_fields: [
                {
                    name: "substring_field",
                    label: "Field to check for substring",
                    control_type: "text",
                    optional: false,
                    default: "record_type"
                },
                {
                    name: "substring_value",
                    label: "Substring to match",
                    control_type: "text",
                    optional: false,
                    default: "request"
                },
                {
                    name: "reminder_field",
                    label: "Reminder datetime field",
                    control_type: "text",
                    optional: true,
                    default: "reminder_email_datetime"
                },
                {
                    name: "request_field",
                    label: "Request datetime field",
                    control_type: "text",
                    optional: true,
                    default: "request_date"
                },
                {
                    name: "reminder_hours",
                    label: "Reminder hours threshold",
                    control_type: "integer",
                    optional: true,
                    default: 12
                },
                {
                    name: "request_hours",
                    label: "Request hours threshold",
                    control_type: "integer",
                    optional: true,
                    default: 48
                }
            ],
            execute: ->(_connection, input, config) {
                records = input['records'] || []
                
                # Get configurable parameters
                substring_field = config['substring_field'] || 'record_type'
                substring_value = config['substring_value'] || 'request'
                reminder_field = config['reminder_field'] || 'reminder_email_datetime'
                request_field = config['request_field'] || 'request_date'
                reminder_hours = (config['reminder_hours'] || 12).to_i
                request_hours = (config['request_hours'] || 48).to_i

                # Calculate thresholds
                now = Time.now
                reminder_threshold = now - (reminder_hours * 60 * 60)
                requested_threshold = now - (request_hours * 60 * 60)

                # Ensure 'records' is an array
                unless records.is_a?(Array)
                    return { 
                        "error" => "Input 'records' was not an array.",
                        "records" => [],
                        "filtered_count" => 0,
                        "original_count" => 0
                    }
                end

                original_count = records.length

                # Filter records
                filtered_records = records.select do |record|
                    call(:is_record_valid_config?, 
                         record, 
                         substring_field,
                         substring_value,
                         reminder_field,
                         request_field,
                         reminder_threshold, 
                         requested_threshold)
                end

                { 
                    "records" => filtered_records,
                    "filtered_count" => filtered_records.length,
                    "original_count" => original_count
                }
            }
        },
        # Holiday Requests - Data Processing
        process_evaluate_approval_status: {
            title: "Holiday Requests - Assess Request Approval Status",
            subtitle: "Summarize approval statuses from a list of date entries",
            display_priority: 0,
            deprecated: true,
            help: ->() {
                "This action takes an array of objects, where each object should have a " +
                "'status' field containing an approval decision (e.g., 'Approve', 'Reject'). It filters " +
                "out empty status values, counts the 'Approve' and 'Reject' decisions (case-insensitive), " +
                "and returns a consolidated status: 'Approve', 'Rejected', 'Partial approval', or empty/nil " +
                "if no valid statuses are found."
            },
            config_fields: [],
            input_fields: ->(object_definitions) {
                [
                    {
                        name: 'entries_list',
                        label: 'Entries List',
                        type: 'array',
                        of: 'object',
                        properties: object_definitions['date_entry_fields'],
                        optional: false,
                        control_type: 'schema-designer',
                        hint: 'Provide the array of entry objects (e.g., the `date_entries` output from the Deserialize Entries action).'
                    }
                ]
            },
            output_fields: ->(object_definitions) {
                object_definitions['approval_result_output']
            },
            execute: ->(_connection, input) {
                # Get the input array, default to empty if not provided
                entries = input['entries_list'] || []
                # Evaluate
                result = call(:evaluate_entries_approval_method, entries)
                # Return the result
                { "result" => result }
            }
        },
        get_field_names: {
            title: "Holiday Requests - Get Field Names",
            subtitle: "Get field names",
            display_priority: 0,
            deprecated: true,
            help: ->() {
              "This action is untested and should be used with caution."
            },
            
            input_fields: ->(object_definitions) {
                object_definitions['generic_input']
            },
            
            output_fields: ->(object_definitions) {
                object_definitions['field_discovery']
            },
            
            execute: ->(_connection, input) {
                records = input['records'] || []
                
                # Extract field names from all records (merging all possible fields)
                all_fields = {}
                
                records.each do |record|
                    record.keys.each do |key|
                        all_fields[key.to_s] = true
                    end
                end
                
                field_names = all_fields.keys
                
                # Create nice labels for fields
                field_labels = {}
                field_names.each do |field|
                    label = field.to_s.gsub('_', ' ').split.map(&:capitalize).join(' ')
                    field_labels[field.to_s] = label
                end
                
                {
                    available_fields: field_names,
                    field_labels: field_labels
                }
            }
        },
        build_rfc822_email: {
          title: "Build RFC 822 Email",
          subtitle: 'Construct a raw email message for API use',
          help: 'This action builds a raw RFC 822 compliant email message and encodes it in Base64 URL-safe format. This is commonly required for sending emails via APIs like the Gmail API.',
          display_priority: 10,
          input_fields:  ->(object_definitions) { object_definitions['email_input_rfc822'] },
          output_fields: ->(object_definitions) { object_definitions['email_output_rfc822'] },
          execute: ->(_connection, input) {
            # ------- Main -------
            # 1. Gather Inputs from nested structure
            from      = input.dig('sender_details', 'from')
            to        = input.dig('recipient_details', 'to')
            cc        = input.dig('recipient_details', 'cc')
            bcc       = input.dig('recipient_details', 'bcc')
            reply_to  = input.dig('recipient_details', 'reply_to')
            subject   = input.dig('email_content', 'subject')
            text_body = input.dig('email_content', 'text_body')
            html_body = input.dig('email_content', 'html_body')
            atts      = input['attachments'] || []

            has_text = text_body && !text_body.to_s.empty?
            has_html = html_body && !html_body.to_s.empty?

            # Consider attachments "present" only if they have filename and some content
            has_atts = Array(atts).any? do |a|
                a.is_a?(Hash) &&
                (a['filename'] || a[:filename]).to_s.strip != '' &&
                (
                    (a['content_base64'] || a[:content_base64]).to_s.strip != '' ||
                    (a['content']        || a[:content]).to_s.strip        != ''
                )
            end

            # 2. Build Message Headers
            top = []
            top << "From: #{call(:normalize_address, from)}" if from
            to_line  = call(:join_addresses, to)
            cc_line  = call(:join_addresses, cc)
            bcc_line = call(:join_addresses, bcc) # note: api requires this

            top << "To: #{to_line}"       unless to_line.empty?
            top << "Cc: #{cc_line}"       unless cc_line.empty?
            top << "Bcc: #{bcc_line}"     unless bcc_line.empty?
            top << "Subject: #{call(:rfc2047, call(:sanitize_header, subject.to_s))}" if subject
            rp_line = call(:join_addresses, reply_to)
            top << "Reply-To: #{rp_line}" unless rp_line.empty?
            top << "Date: #{Time.now.utc.rfc2822}"
            top << "Message-ID: <#{SecureRandom.uuid}@workato>"

            # 3. Build Message Body
            crlf = "\r\n"
            body = nil

            if has_atts
                # Top-level multipart/mixed
                mixed_boundary = call(:random_boundary, 'mixed')
                top << "MIME-Version: 1.0"
                top << "Content-Type: multipart/mixed; boundary=\"#{mixed_boundary}\""

                # First part: either multipart/alternative (text+html), or a single text/* part
                mixed_parts = []
                if has_text && has_html
                    alt_boundary = call(:random_boundary, 'alt')
                    alt_parts = [
                        call(:part_text, text_body, 'plain'),
                        call(:part_text, html_body, 'html')
                    ]
                    mixed_parts << call(:part_multipart, 'alternative', alt_boundary, alt_parts)
                elsif has_html
                    mixed_parts << call(:part_text, html_body, 'html')
                else
                    # Default to text/plain even if empty to ensure a body exists
                    mixed_parts << call(:part_text, (text_body || ''), 'plain')
                end

                # Attachment parts
                Array(atts).each do |att|
                    part = call(:part_attachment, att)
                    mixed_parts << part if part
                end

                body = call(:multipart_body, mixed_boundary, mixed_parts)
            else
                # No attachments >> behave like before (alternative or single part)
                if has_text && has_html
                    alt_boundary = call(:random_boundary, 'alt')
                    top << "MIME-Version: 1.0"
                    top << "Content-Type: multipart/alternative; boundary=\"#{alt_boundary}\""
                    parts = [
                        call(:part_text, text_body, 'plain'),
                        call(:part_text, html_body, 'html')
                    ]
                    body = call(:multipart_body, alt_boundary, parts)
                elsif has_html
                    top << "MIME-Version: 1.0"
                    top << "Content-Type: text/html; charset=UTF-8"
                    top << "Content-Transfer-Encoding: base64"
                    body = call(:b64wrap, html_body.to_s.encode('UTF-8'))
                else
                    top << "MIME-Version: 1.0"
                    top << "Content-Type: text/plain; charset=UTF-8"
                    top << "Content-Transfer-Encoding: base64"
                    body = call(:b64wrap, text_body.to_s.encode('UTF-8'))
                end
            end

            # --- Final Assembly and Return ---
            # 1. Combine headers and body into a single RFC 822 message string.
            rfc822 = (top + ['', body]).join(crlf)

            # 2. Base64 URL encode the entire message for the Gmail API.
            raw = call(:b64url, rfc822)

            # 3. Return the final output.
            { raw: raw }
        }
    },
    methods: {
        # Build
        build_entries: ->(input, count) {
            (1..count).each_with_object([]) do |i, arr|
                rec = input["entry_#{i}"] || {}
                next if rec['date'].to_s.strip.empty? || rec['units'].nil?
                arr << {
                    'date'   => rec['date'],
                    'units'  => rec['units'].to_f,
                    'status' => rec['status']
                }
            end
        },
        
        # --- RFC 822 Email Building Methods ---
        sanitize_header: ->(s) {
            # Prevent CRLF/header-injection; trim extraneous whitespace.
            s.to_s.gsub(/[\r\n]+/, ' ').strip
        },
        b64url: ->(data) {
          # Encodes data into Base64 URL-safe format.
          Base64.strict_encode64(data).tr('+/', '-_').gsub(/=+\z/, '')
        },       
        b64wrap: ->(bytes) {
          # Wraps a Base64 string into 76-character lines.
          crlf = "\r\n"
          Base64.strict_encode64(bytes).scan(/.{1,76}/).join(crlf)
        },    
        rfc2047: ->(str) {
          # Encodes a string for email headers using RFC 2047 if it contains non-ASCII characters.
          s = str.to_s
          return s if s.ascii_only?
          "=?UTF-8?B?#{Base64.strict_encode64(s.encode('UTF-8'))}?="
        },   
        normalize_address: ->(addr) {
          # Formats an email address, encoding the name part if necessary.
          if addr.is_a?(Hash)
            name = addr['name'] || addr[:name]
            email = addr['email'] || addr[:email]
          else
            s = addr.to_s.strip
            if s =~ /\A\s*"?([^"<]*)"?\s*<([^>]+)>\s*\z/
              name = $1.to_s.strip
              email = $2.strip
            else
              name = nil
              email = s
            end
          end

          # Harden against header injection
          name  = call(:sanitize_header, name)  if name
          email = call(:sanitize_header, email)

          if name && !name.empty?
            %(#{call(:rfc2047, name)} <#{email}>)
          else
            email
          end
        },   
        join_addresses: ->(val) {
          # Joins multiple email addresses into a single header string.
          Array(val).compact.reject { |x| x.to_s.strip.empty? }.map { |a| call(:normalize_address, a) }.join(', ')
        },  
        random_boundary: ->(tag) {
          # Generates a random boundary string for multipart messages.
          "==_Workato_#{tag}_#{SecureRandom.hex(12)}"
        }, 
        part_text: ->(text, subtype) {
          # Creates a text part for a multipart message.
          crlf = "\r\n"
          [
            "Content-Type: text/#{subtype}; charset=UTF-8",
            "Content-Transfer-Encoding: base64",
            "",
            call(:b64wrap, text.to_s.encode('UTF-8'))
          ].join(crlf)
        },
        part_multipart: ->(subtype, boundary, parts) {
            crlf = "\r\n"
            [
                "Content-Type: multipart/#{subtype}; boundary=\"#{boundary}\"",
                "",
                call(:multipart_body, boundary, parts)
            ].join(crlf)
        },
        part_attachment: ->(att) {
            # Build an attachment part (base64). Accepts either 'content_base64', or raw 'content' (text).
            return nil unless att.is_a?(Hash)

            crlf = "\r\n"
            filename   = (att['filename'] || att[:filename]).to_s
            return nil if filename.strip.empty?

            mime_type  = (att['mime_type'] || att[:mime_type] || call(:detect_mime_type, filename)).to_s
            disposition = (att['disposition'] || att[:disposition]).to_s.strip.downcase
            disposition = %w[inline attachment].include?(disposition) ? disposition : 'attachment'
            content_id = (att['content_id'] || att[:content_id]).to_s.strip

            # Prefer base64, else treat `content` as raw text (for small text files)
            if (b64 = (att['content_base64'] || att[:content_base64]).to_s).strip != ''
                bytes = Base64.decode64(b64)
            else
                raw = (att['content'] || att[:content]).to_s
                bytes = raw.dup.force_encoding('BINARY')
            end

            safe_name = call(:sanitize_header, filename)

            headers = [
                "Content-Type: #{mime_type}; name=\"#{safe_name}\"",
                "Content-Transfer-Encoding: base64",
                "Content-Disposition: #{disposition}; filename=\"#{safe_name}\""
            ]
            headers << "Content-ID: <#{call(:sanitize_header, content_id)}>" unless content_id.empty?

            (headers + ["", call(:b64wrap, bytes)]).join(crlf)
        
        }, 
        multipart_body: ->(boundary, parts) {
          # Joins multiple message parts with a boundary.
          crlf = "\r\n"
          (parts.flat_map { |p| ["--#{boundary}", p] } + ["--#{boundary}--"]).join(crlf)
        },
        detect_mime_type: ->(filename) {
            ext = File.extname(filename.to_s.downcase).sub('.', '')
            mapping = {
                'txt'  => 'text/plain',
                'csv'  => 'text/csv',
                'htm'  => 'text/html',
                'html' => 'text/html',
                'json' => 'application/json',
                'xml'  => 'application/xml',
                'pdf'  => 'application/pdf',
                'jpg'  => 'image/jpeg', 'jpeg' => 'image/jpeg', 'jpe' => 'image/jpeg',
                'png'  => 'image/png',  'gif'  => 'image/gif',  'bmp' => 'image/bmp',
                'webp' => 'image/webp', 'svg'  => 'image/svg+xml',
                'tif'  => 'image/tiff', 'tiff' => 'image/tiff',
                'xls'  => 'application/vnd.ms-excel',
                'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                'doc'  => 'application/msword',
                'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                'ppt'  => 'application/vnd.ms-powerpoint',
                'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
                'zip'  => 'application/zip', 'gz' => 'application/gzip', 'tar' => 'application/x-tar',
                '7z'   => 'application/x-7z-compressed',
                'rtf'  => 'application/rtf',
                'mp3'  => 'audio/mpeg', 'wav' => 'audio/wav',
                'mp4'  => 'video/mp4',  'mov' => 'video/quicktime', 'avi' => 'video/x-msvideo'
            }
            mapping[ext] || 'application/octet-stream'
        },

        # Transformations
        data_transformation_fields_to_json: ->(input_record) {
            # Build nested date_entries from wide-form input_record
            entries = []
            (1..10).each do |i|
                date_val = input_record["date#{i}"]
                next unless date_val.present?
                entries << {
                    'date'   => date_val,
                    'units'  => input_record["units#{i}"]&.to_f,
                    'status' => input_record["status#{i}"]
                }.compact
            end
            entries
        },
        normalize_entries: ->(entries, strict: false) {
            Array(entries).each_with_index.map do |e, idx|
                date = begin
                    v = e['date']
                    v.nil? ? nil : Date.parse(v.to_s)
                rescue
                    raise "Entry #{idx + 1}: invalid date #{e['date'].inspect}" if strict
                    nil
                end
                units = begin
                    v = e['units']
                    v.nil? ? nil : Float(v)
                rescue
                    raise "Entry #{idx + 1}: invalid units #{e['units'].inspect}" if strict
                    nil
                end
                h = {}
                h['date'] = date if date
                h['units'] = units if units
                h['status'] = e['status']&.to_s if e.key?('status') && e['status']
                h
            end.reject { |h| h['date'].nil? || h['units'].nil? }
        },

        # JSON
        serialize_entries: ->(entries) {
            # JSON-serialize an array of hashes
            entries.to_json
        },
        deserialize_entries_method: ->(json_string) {
            # Parse JSON back into an array of hashes
            JSON.parse(json_string)
        },
        verify_serialization: ->(entries, json_string) {
            # Confirm that parsing was successful
            JSON.parse(json_string) == entries
        },
        url_encode_json: ->(data) {
            json_string = JSON.pretty_generate(data)
            URI.encode_www_form_component(json_string)
        },
        repair_json: ->(json_str) {
            return json_str if json_str.nil? || json_str.empty?

            json_str = json_str.to_s.strip

            # Handle commone prefix/suffix issues
            json_str = json_str.sub(/^.*?(\[|\{)/, '\1')

            # Fix unquoted property names
            json_str = json_str.gsub(/([a-zA-Z0-9_]+)(\s*):/, '"\1"\2:')

            # Fix unquoted string values
            json_str = json_str.gsub(/:(\s*)([a-zA-Z0-9_\/-]+)(\s*)(,|\}|\])/, ':"\2"\4')

            # Fix empty values
            json_str = json_str.gsub(/:(\s*)(,|\}|\])/, ':""\\2')

            # Ensure structure is complete
            unless json_str.start_with?('{') || json_str.start_with?('[')
                json_str = '[' + json_str
            end

            unless json_str.end_with?('}') || json_str.end_with?(']')
                json_str = json_str + ']'
            end

            # Balance brackets as required
            open_braces = json_str.count('{')
            close_braces = json_str.count('}')
            open_brackets = json_str.count('[')
            close_brackets = json_str.count(']')
            
            # Add missing closing braces/brackets
            if open_braces > close_braces
                json_str += '}' * (open_braces - close_braces)
            end
            
            if open_brackets > close_brackets
                json_str += ']' * (open_brackets - close_brackets)
            end
            
            # Remove trailing commas before closing brackets/braces
            json_str = json_str.gsub(/,(\s*)(\}|\])/, '\2')
            
            # Return repaired JSON string
            json_str
        },
        coerce_type: ->(val) {
            case val
            when String
                s = val.strip
                if    s =~ /\A-?\d+\z/            # pure integer
                    s.to_i
                elsif s =~ /\A-?\d+\.\d+\z/       # decimal number
                    s.to_f
                elsif s =~ /\A(true|false)\z/i    # boolean
                    s.downcase == 'true'
                elsif s =~ /\A\d{4}-\d{2}-\d{2}(?:T.*)?\z/ # ISO date or datetime
                    DateTime.parse(s) rescue s
                else
                    s
                end
            else
              val
            end
        },
        deserialize_and_coerce: ->(json_str) {
            fixed = repair_json(json_str)
            raw   = JSON.parse(fixed) rescue []
            raw.map { |obj| obj.transform_values { |v| coerce_type(v) } }
        },

        # Safely parse and format dates and times
        format_date: ->(d) {
            d.strftime('%Y-%m-%d') if d.present?
        },
        safe_time_parse: ->(v) {
            # Return input if input is already a time object
            return v if v.is_a?(Time)

            # Convert to string and strip whitespace
            value_str = v.to_s.strip
            return nil if value_str.empty? # return nil if empty str

            begin
                Time.parse(value_str)
            rescue ArgumentError
                nil # return nil if parsing fails
            end
        },
        output_fields_for_format: ->(object_definitions, format, max_flat) {
            fields = []
            if %w[nested_array both].include?(format)
                fields << {
                    control_type: 'nested_fields',
                    type: 'array',
                    of: 'object',
                    name: 'date_entries',
                    label: 'Date Entries',
                    properties: object_definitions['date_entry_fields']
                }
            end
            if %w[lists both].include?(format)
                fields += [
                    { name: 'dates', label: 'Date', type: 'array', of: 'date' },
                    { name: 'units',    label: 'Units',    type: 'array', of: 'number' },
                    { name: 'statuses', label: 'Statuses', type: 'array', of: 'string' }
                ]
            end
            if %w[flat_fields both].include?(format)
                (1..max_flat).each do |i|
                    fields += [
                        { name: "entry_#{i}_date",   label: "Entry #{i} Date",   type: 'date'   },
                        { name: "entry_#{i}_units",  label: "Entry #{i} Units",  type: 'number' },
                        { name: "entry_#{i}_status", label: "Entry #{i} Status", type: 'string' }
                    ]
                end
            end
            fields
        },
        extract_num_days: ->(data) {},

        # Logical Validation
        is_record_valid_config?: ->(record, substring_field, substring_value, reminder_field, request_field, reminder_boundary, requested_boundary) {
            # 1. Parse datetime fields safely
            reminder_time = reminder_field.present? ? call(:safe_time_parse, record[reminder_field]) : nil
            requested_time = request_field.present? ? call(:safe_time_parse, record[request_field]) : nil

            # 2. Evaluate type condition (only if substring_field is present)
            field_value = record[substring_field]
            type_matches = field_value.present? && field_value.to_s.downcase.include?(substring_value.to_s.downcase)

            # 3. Evaluate reminder time condition (only if reminder_field is present)
            reminder_is_valid = !call(:present?, reminder_field) || reminder_time.nil? || reminder_time <= reminder_boundary

            # 4. Evaluate requested time condition (only if request_field is present)
            requested_is_valid = !call(:present?, request_field) || requested_time.nil? || requested_time <= requested_boundary

            # 5. Return true only if all conditions are met
            type_matches && reminder_is_valid && requested_is_valid
        },
        is_record_expired?: ->(record, date_field, expiration_boundary) {
          # Safely parse datetime field from the record
          last_verified_date = call(:safe_time_parse, record[date_field])
          
          # If date is missing/invalid, consider the record expired
          return true if last_verified_date.nil?
          
          # Return true if verification date is prior to expiration boundary
          last_verified_date < expiration_boundary
        },
        evaluate_entries_approval_method: ->(entries) {
            # Ensure input is an array
            entries = Array(entries)

            # Extract values from input
            responses = entries.map do |entry|
                # Safely access the 'status' key only if entry is a Hash
                entry.is_a?(Hash) ? entry['status'] : nil
            end.compact

            # Remove empty strings or strings with only whitespace
            valid_responses = responses.reject { |response| response.to_s.strip.empty? }

            # Return nil if no valid responses remain
            return nil if valid_responses.empty?

            # Count valid responses (case-insensitive and ignoring leading/trailing whitespace)
            approve_count = valid_responses.count { |r| r.to_s.strip.casecmp("Approve") == 0 }
            reject_count  = valid_responses.count { |r| r.to_s.strip.casecmp("Reject") == 0 }

            # Assess counts to determine final status
            if approve_count > 0 && reject_count == 0
                "Approve"
            elsif approve_count > 0 && reject_count > 0
                "Partial approval"
            elsif reject_count > 0 && approve_count == 0
                "Rejected"
            else
                nil
            end
        },
        present?: ->(value) {
            !value.nil? && (value.respond_to?(:empty?) ? !value.empty? : true)
        },
        determine_email_type: ->(input_data) {
            raw = (input_data.dig('email_content', 'email_type') || '')
            .to_s.strip
            .downcase
            
            # Map picklist labels to normalized vals
            case raw
            when 'table_link'
              'table_link'
            when 'link'
              'link'
            when 'table only', 'table'
              'table'
            when 'body', 'custom body only'
              'body'
            else 
              raw
            end
        },
        process_holiday_requests: ->(entries) {
            return [] unless entries.is_a?(Array)
            processed = []

            entries.each do |entry|
                next unless entry.respond_to?(:[]) &&
                            call(:present?, entry['date']) &&
                            call(:present?, entry['units'])

                # Format date as YYYY-MM-DD
                fmt = begin
                    if entry['date'].is_a?(Date)
                        entry['date'].strftime('%Y-%m-%d')
                    else
                        Date.parse(entry['date'].to_s).strftime('%Y-%m-%d')
                    end
                rescue
                    nil
                end
                next unless fmt

                # Units → float
                units_f = begin
                    Float(entry['units'])
                rescue
                    entry['units'].to_f
                end

                processed << {
                    'date'   => fmt,
                    'units'  => units_f,
                    'status' => entry['status']
                }
            end

            processed
        },
        process_empty_fields: ->(entry, handling, default_value) {
            return entry unless entry.is_a?(Hash)
          
            case handling
            when 'to_null'
                entry.transform_values { |v| (v.is_a?(String) && v.empty?) ? nil : v }
            when 'to_empty'
                # Convert null to empty strings
                entry.transform_values { |v| v.nil? ? '' : v }
            when 'omit'
                # Remove empty or null fields
                entry.reject { |_, v| v.nil? || (v.is_a?(String) && v.empty?) }
            when 'default'
                # Replace empty or null with default value
                if default_value
                    entry.transform_values { |v| (v.nil? || (v.is_a?(String) && v.empty?)) ? default_value : v }
                else
                    entry
                end
            else
              # Default: preserve as is
                entry
            end
        },

        # Common methods
        email_template_html_wrapper: ->(inner_html, page_title) {
          <<~HTML
          <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
          <html xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office">
          <head>
            <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1.0" />
            <meta name="x-apple-disable-message-reformatting" />
            <title>#{page_title}</title>
            <!--[if mso]>
            <xml>
              <o:OfficeDocumentSettings>
                <o:PixelsPerInch>96</o:PixelsPerInch>
                <o:AllowPNG/>
              </o:OfficeDocumentSettings>
            </xml>
            <style>
              table {border-collapse:collapse;border-spacing:0;width:100%;}
              div, td {padding:0;}
              div {margin:0 !important;}
            </style>
            <noscript>
            <xml>
              <o:OfficeDocumentSettings>
                <o:PixelsPerInch>96</o:PixelsPerInch>
              </o:OfficeDocumentSettings>
            </xml>
            </noscript>
            <![endif]-->
            <style type="text/css">
              @media screen and (max-width: 525px) {
                .email-container {
                    width: 100% !important;
                    max-width: 100% !important;
                }
                .responsive-table {
                    width: 100% !important;
                }
                .padding {
                    padding: 10px 5% 15px 5% !important;
                }
                .padding-meta {
                    padding: 30px 5% 0px 5% !important;
                    text-align: center;
                }
                .no-padding {
                    padding: 0 !important;
                }
                .section-padding {
                    padding: 50px 15px 50px 15px !important;
                }
                .mobile-button-container {
                    margin: 0 auto;
                    width: 100% !important;
                }
                .mobile-button {
                    padding: 12px 30px !important;
                    border: 0 !important;
                    font-size: 16px !important;
                    display: block !important;
                }
              }
              div[style*="margin: 16px 0;"] { margin: 0 !important; }
        /* Stops email clients resizing small text. */
              * {
                -ms-text-size-adjust: 100%;
                -webkit-text-size-adjust: 100%;
              }
        /* Force Outlook.com to display emails full width. */
              .ExternalClass {
                width: 100%;
              }
        /* Stop Outlook from adding extra spacing to tables. */
              table, td {
                mso-table-lspace: 0pt;
                mso-table-rspace: 0pt;
              }
        /* Fix webkit padding issue. */
              table {
                border-spacing: 0 !important;
                border-collapse: collapse !important;
                table-layout: fixed !important;
                margin: 0 auto !important;
              }
        /* This uses a better rendering method when resizing images in IE. */
              img {
                -ms-interpolation-mode: bicubic;
              }
        /* Override styles added when Yahoo's auto-senses a link. */
              .yshortcuts a {
                border-bottom: none !important;
              }
        /* Prevents underlining the button text in Windows 10 */
              .button-link {
                text-decoration: none !important;
              }
            
              body, p, div {
                margin: 0;
                padding: 0;
                font-family: Tahoma, 'Trebuchet MS', Helvetica, Arial, sans-serif;
                font-size: 16px;
                line-height: 1.5;
                color: #404757;
              }
              body {
                background-color: #F7F5F0;
                margin: 0;
                padding: 0;
                -webkit-font-smoothing: antialiased;
                -ms-text-size-adjust: 100%;
                -webkit-text-size-adjust: 100%;
              }
              .email-container {
                max-width: 600px;
                margin: 0 auto;
              }
              .inner-container {
                padding: 30px;
                background-color: #FFFFFF;
                border-radius: 6px;
              }
              h1, h2, h3 {
                color: #0F1941;
                margin-top: 0;
                font-weight: bold;
              }
              p {
                margin-bottom: 16px;
              }
              .holiday-table {
                width: 100%;
                border-collapse: collapse;
                margin: 16px 0;
              }
              .holiday-table th, .holiday-table td {
                padding: 8px;
                border: 1px solid #ddd;
                text-align: left;
                font-size: 14px;
              }
              .holiday-table th {
                background-color: #F7F5F0;
                color: #0F1941;
                font-weight: bold;
              }
              .button-container {
                margin-top: 20px;
                margin-bottom: 20px;
              }
              .button-link {
                background-color: #2175D9;
                border-radius: 4px;
                color: #ffffff;
                display: inline-block;
                font-size: 16px;
                font-weight: bold;
                line-height: 40px;
                text-align: center;
                text-decoration: none;
                width: 220px;
                -webkit-text-size-adjust: none;
                mso-hide: all;
              }
            </style>
          </head>
          <body>
            <div style="background-color: #F7F5F0; padding: 20px 0;">
              <table border="0" cellpadding="0" cellspacing="0" width="100%" class="responsive-table">
                <tr>
                    <td align="center">
                        <table border="0" cellpadding="0" cellspacing="0" width="100%" style="max-width: 600px;" class="email-container">
                            <tr>
                                <td align="center" valign="top" style="padding: 0; background-color: #FFFFFF; border-radius: 6px;">
                                    <table border="0" cellpadding="0" cellspacing="0" width="100%" style="max-width: 600px;">
                                        <tr>
                                            <td align="left" valign="top" style="padding: 30px;" class="inner-container">
                                                #{inner_html.gsub('<a class="button"', '<div class="button-container"><a class="button-link"').gsub('</a>', '</a></div>')}
                                            </td>
                                        </tr>
                                    </table>
                                </td>
                            </tr>
                        </table>
                    </td>
                </tr>
              </table>
            </div>
          </body>
          </html>
          HTML
        },
        parse_csv_to_table_data: ->(csv_text, max_rows, max_columns) {
            table_data = {}
          
            begin
              require 'csv'
              csv_rows = CSV.parse(csv_text.to_s.strip)
            
              # Populate table_data from CSV
              csv_rows.each_with_index do |row, row_idx|
                break if row_idx >= max_rows
              
                row_data = {}
                row.each_with_index do |cell, col_idx|
                    break if col_idx >= max_columns
                    row_data["c#{col_idx + 1}"] = cell
                end
              
                table_data["row_#{row_idx + 1}"] = row_data
              end
            rescue => e
                # Log error but return any existing table_data
                puts "CSV import error: #{e.message}"
            end
          
            return table_data
        }
    }
}
