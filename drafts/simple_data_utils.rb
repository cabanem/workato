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
        email_input_rfc822: {
            fields: -> (object_definitions, _connection) {
                [
                    {
                        name: 'sender_details',
                        type: :object,
                        control_type: 'nested_fields',
                        label: 'Sender',
                        properties: [
                            {
                                name: 'from',
                                type: :object,
                                control_type: 'nested_fields',
                                label: 'From',
                                optional: false,
                                properties: object_definitions['email_address_fields']
                            }
                        ]
                    },
                    {
                        name: 'recipient_details',
                        type: :object,
                        control_type: 'nested_fields',
                        label: 'Recipients',
                        properties: [
                            {
                                name: 'to',
                                type: :array,
                                of: :object,
                                control_type: 'nested_fields',
                                label: 'To',
                                hint: 'Map an array pill of objects with name/email.',
                                optional: false,
                                properties: object_definitions['email_address_fields']
                            },
                            {
                                name: 'cc',
                                type: :array,
                                of: :object,
                                control_type: 'nested_fields',
                                label: 'Cc',
                                optional: true,
                                properties: object_definitions['email_address_fields']
                            },
                            {
                                name: 'bcc',
                                type: :array,
                                of: :object,
                                control_type: 'nested_fields',
                                label: 'Bcc',
                                optional: true,
                                properties: object_definitions['email_address_fields']
                            },
                            {
                                name: 'reply_to',
                                type: :array,
                                of: :object,
                                control_type: 'nested_fields',
                                label: 'Reply-To',
                                optional: true,
                                properties: object_definitions['email_address_fields']

                            }
                        ]
                    },
                    {
                        name: 'email_content',
                        type: :object,
                        control_type: 'nested_fields',
                        label: 'Content',
                        properties: [
                            { name: 'subject',   type: 'string', control_type: 'text',       label: 'Subject',   optional: false },
                            { name: 'text_body', type: 'string', control_type: 'text-area',  label: 'Text Body', optional: true, hint: 'Plain text version.' },
                            { name: 'html_body', type: 'string', control_type: 'text-area',  label: 'HTML Body', optional: true, hint: 'HTML version.' }
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
          fields: -> (_object_definitions, _connection) {
            [
              { 
                      name: 'raw',
                      type: 'string',
                      control_type: 'text-area'
                      label: 'Raw Message (base64url)',
                      hint: 'Base64 URL-safe encoded RFC 822 email message, suitable for use with email APIs like Gmail.' 
              }
            ]
          }
        },
        email_address_fields: {
            fields: ->(_connection, _config_fields) {
                [
                    { name: 'name', label: 'Name', type: 'string', control_type: 'text', optional: true, hint: 'Optional display name' },
                    { name: 'email', label: 'Email', type: 'string', control_type: 'text',   optional: false, hint: 'user@example.com' }
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
            [
                [ 'REDACTED Contractor Care Team', 'REDACTED Contractor Care Team' ]
            ]
        },
        email_greeting: -> {
            [
                [ 'Hello,', 'Hello' ]
            ]
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
  
    triggers: {},
    actions: {
        build_rfc822_email: {
          title: "Build RFC 822 Email",
          subtitle: 'Construct a raw email message for API use',
          help: 'This action builds a raw RFC 822 compliant email message and encodes it in Base64 URL-safe format. This is commonly required for sending emails via APIs like the Gmail API.',
          display_priority: 10,
          input_fields:  ->(object_definitions) { object_definitions['email_input_rfc822'] },
          output_fields: ->(object_definitions) { object_definitions['email_output_rfc822'] },
          execute: ->(_connection, input) {
            # ------- Main -------
            # Flatten function params
            if input.key?('from_email') || input.key?('to_emails')
              parse_list = ->(s) {
                s.to_s.split(/[,;\n]/).map { |t| t.strip }.reject(&:empty?)
              }
              parse_atts = ->(s) {
                return [] if s.to_s.strip.empty?
                JSON.parse(s)
              }
              input = {
                'sender_details' => {
                  'from' => { 'name' => input['from_name'], 'email' => input['from_email'] }.compact
                },
                'recipient_details' => {
                  'to'       => parse_list.call(input['to_emails']),
                  'cc'       => parse_list.call(input['cc_emails']),
                  'bcc'      => parse_list.call(input['bcc_emails']),
                  'reply_to' => parse_list.call(input['reply_to_emails'])
                },
                'email_content' => {
                  'subject'   => input['subject'],
                  'text_body' => input['text_body'],
                  'html_body' => input['html_body']
                },
                'attachments' => parse_atts.call(input['attachments_json'])
              }
            end
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

            # Basic validation to 'fail fast'
            from_norm = call(:normalize_address, from)
            raise "From is required and must include a valid email" if from_norm.to_s.strip.empty?
            to_line = call(:join_addresses, to)
            cc_line = call(join_addresses, cc)
            bcc_line = call(join_addresses, bcc)
            raise "At least one recipient is required (To, Cc, or Bcc)." if [to_line, cc_line, bcc_line].all? { |s| s.to_s.strip.empty? }

            # 2. Build Message Headers
            top = []
            top << "From: #{from_norm}"

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
                    mixed_parts << call(:part_text, (text_body.nil? ? ' ' : text_body), 'plain')
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
                    body = call(:b64wrap, (text_body.nil? ? ' ' : text_body).to_s.encode('UTF-8'))
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
        }
    },
    methods: {
        # --- RFC 822 Email Building Methods ---
        # Prevent CRLF/header-injection; trim extraneous whitespace.
        sanitize_header: ->(s) { s.to_s.gsub(/[\r\n]+/, ' ').strip },
        # Encodes data into Base64 URL-safe format.
        b64url: ->(data) { Base64.strict_encode64(data).tr('+/', '-_').gsub(/=+\z/, '') },
        # Wraps a Base64 string into 76-character lines.      
        b64wrap: ->(bytes) { Base64.strict_encode64(bytes).scan(/.{1,76}/).join("\r\n") },
        # Encodes a string for email headers using RFC 2047 if it contains non-ASCII characters.
        rfc2047: ->(str) { s = str.to_s; s.ascii_only? ? s : "=?UTF-8?B?#{Base64.strict_encode64(s.encode('UTF-8'))}?=" },  
        # Formats an email address, encoding the name part if necessary.
        normalize_address: ->(addr) {
          if addr.is_a?(Hash)
            name  = addr['name']  || addr[:name]
            email = addr['email'] || addr[:email]
          else
            s = addr.to_s.strip
            if s =~ /\A\s*"?([^"<]*)"?\s*<([^>]+)>\s*\z/
              name  = $1.to_s.strip
              email = $2.strip
            else
              name = nil; email = s
            end
          end
          name  = call(:sanitize_header, name)  if name
          email = call(:sanitize_header, email)
          return '' if email.nil? || email.empty?
          name && !name.empty? ? %(#{call(:rfc2047, name)} <#{email}>) : email
        },
        # Joins multiple email addresses into a single header string
        join_addresses: ->(val) {
          # Normalize first, then drop empties
          normalized = Array(val).map { |a| call(:normalize_address, a) }
          normalized.reject { |s| s.to_s.strip.empty? }.join(', ')
        },
        # Generates a random boundary string for multipart messages.
        random_boundary: ->(tag) {  "==_Workato_#{tag}_#{SecureRandom.hex(12)}" },
        # Creates a text part for a multipart message.
        part_text: ->(text, subtype) {
          [
            "Content-Type: text/#{subtype}; charset=UTF-8",
            "Content-Transfer-Encoding: base64",
            "",
            call(:b64wrap, text.to_s.encode('UTF-8'))
          ].join("\r\n")
        },
        part_multipart: ->(subtype, boundary, parts) {
          [
            "Content-Type: multipart/#{subtype}; boundary=\"#{boundary}\"",
            "",
            call(:multipart_body, boundary, parts)
          ].join("\r\n")
        },
        # Build an attachment part (base64). Accepts either 'content_base64', or raw 'content' (text).
        part_attachment: ->(att) {
          return nil unless att.is_a?(Hash)
          crlf = "\r\n"
          filename = (att['filename'] || att[:filename]).to_s
          return nil if filename.strip.empty?
          mime_type   = (att['mime_type'] || att[:mime_type] || call(:detect_mime_type, filename)).to_s
          disposition = (att['disposition'] || att[:disposition]).to_s.strip.downcase
          disposition = %w[inline attachment].include?(disposition) ? disposition : 'attachment'
          content_id  = (att['content_id'] || att[:content_id]).to_s.strip
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
        # Joins multiple message parts with a boundary.
        multipart_body: ->(boundary, parts) {
          (parts.flat_map { |p| ["--#{boundary}", p] } + ["--#{boundary}--"]).join("\r\n")
        },
        detect_mime_type: ->(filename) {
          ext = File.extname(filename.to_s.downcase).sub('.', '')
          mapping = {
            'txt'=>'text/plain','csv'=>'text/csv','htm'=>'text/html','html'=>'text/html',
            'json'=>'application/json','xml'=>'application/xml','pdf'=>'application/pdf',
            'jpg'=>'image/jpeg','jpeg'=>'image/jpeg','jpe'=>'image/jpeg','png'=>'image/png',
            'gif'=>'image/gif','bmp'=>'image/bmp','webp'=>'image/webp','svg'=>'image/svg+xml',
            'tif'=>'image/tiff','tiff'=>'image/tiff',
            'xls'=>'application/vnd.ms-excel','xlsx'=>'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'doc'=>'application/msword','docx'=>'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'ppt'=>'application/vnd.ms-powerpoint','pptx'=>'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            'zip'=>'application/zip','gz'=>'application/gzip','tar'=>'application/x-tar','7z'=>'application/x-7z-compressed',
            'rtf'=>'application/rtf','mp3'=>'audio/mpeg','wav'=>'audio/wav','mp4'=>'video/mp4','mov'=>'video/quicktime','avi'=>'video/x-msvideo'
          }
          mapping[ext] || 'application/octet-stream'
        }
    }
}
