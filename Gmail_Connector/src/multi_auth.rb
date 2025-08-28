{
  title: 'Gmail (OAuth + Mock)',

  connection: {
    fields: [
      {
        name: 'auth_type',
        label: 'Authentication mode',
        control_type: 'select',
        options: [
          ['Gmail OAuth (live)', 'gmail_oauth2'],
          ['Mock (no auth)', 'mock']
        ],
        default: 'gmail_oauth2',
        extends_schema: true
      }
    ],

    authorization: {
      type: 'multi',

      selected: lambda { |connection| connection['auth_type'] || 'gmail_oauth2' },

      options: {
        gmail_oauth2: {
          type: 'oauth2',

          # Connection-scoped toggles for least privilege
          fields: [
            { name: 'client_id', optional: false, hint: 'Google Cloud OAuth 2.0 Client ID' },
            { name: 'client_secret', control_type: 'password', optional: false, hint: 'Google Cloud OAuth 2.0 Client Secret' },
            { name: 'enable_modify', label: 'Allow modify (gmail.modify)', type: 'boolean', control_type: 'checkbox' },
            { name: 'enable_send',   label: 'Allow send (gmail.send)',   type: 'boolean', control_type: 'checkbox' },
            { name: 'enable_compose',label: 'Allow compose/drafts (gmail.compose)', type: 'boolean', control_type: 'checkbox' },
            { name: 'enable_labels', label: 'Allow label admin (gmail.labels)', type: 'boolean', control_type: 'checkbox' }
          ],

          authorization_url: lambda do |connection|
            scopes = [
              'https://www.googleapis.com/auth/gmail.readonly',
              'https://www.googleapis.com/auth/gmail.metadata'
            ]
            scopes << 'https://www.googleapis.com/auth/gmail.modify'  if connection['enable_modify']
            scopes << 'https://www.googleapis.com/auth/gmail.send'    if connection['enable_send']
            scopes << 'https://www.googleapis.com/auth/gmail.compose' if connection['enable_compose']
            scopes << 'https://www.googleapis.com/auth/gmail.labels'  if connection['enable_labels']

            "https://accounts.google.com/o/oauth2/v2/auth" \
              "?response_type=code" \
              "&access_type=offline" \
              "&prompt=consent" \
              "&include_granted_scopes=true" \
              "&scope=#{CGI.escape(scopes.uniq.join(' '))}"
          end,

          token_url: -> { 'https://oauth2.googleapis.com/token' },
          client_id: ->(connection) { connection['client_id'] },
          client_secret: ->(connection) { connection['client_secret'] },
          apply: ->(_connection, access_token) { headers('Authorization': "Bearer #{access_token}") },

          refresh_on: [401, 403],
          refresh: lambda do |connection, refresh_token|
            post('https://oauth2.googleapis.com/token')
              .payload(
                grant_type: 'refresh_token',
                refresh_token: refresh_token,
                client_id: connection['client_id'],
                client_secret: connection['client_secret']
              )
              .request_format_www_form_urlencoded
          end
        },

        mock: {
          type: 'custom_auth',
          fields: [
            { name: 'mock_user_email', label: 'Mock user email', default: 'mock.user@example.com', optional: true },
            { name: 'mock_seed', label: 'Mock seed (optional)', optional: true }
          ],
          apply: ->(_connection) { headers('X-Mock': 'true') }
        }
      }
    },

    base_uri: lambda do |connection|
      (connection['auth_type'] || 'gmail_oauth2') == 'gmail_oauth2' ?
        'https://gmail.googleapis.com/gmail/v1/users' :
        'https://mock.local/unused'
    end,

    test: lambda do |connection|
      (connection['auth_type'] || 'gmail_oauth2') == 'mock' ? { ok: true } : get('me/profile')
    end
  },

  methods: {
    # === Generic decode helpers ===
    headers_to_hash: lambda do |headers_array|
      (headers_array || []).each_with_object({}) { |h, memo| memo[h['name']] = h['value'] }
    end,

    extract_bodies: lambda do |payload|
      out = { text: nil, html: nil }
      queue = [payload].compact
      while (part = queue.shift)
        mime = part['mimeType']
        data = part.dig('body', 'data')
        if data.present?
          begin
            content = decode_urlsafe_base64(data)
          rescue
            content = nil
          end
          out[:text] ||= content if mime == 'text/plain'
          out[:html] ||= content if mime == 'text/html'
        end
        parts = part['parts']
        queue.concat(parts) if parts.is_a?(Array)
      end
      out
    end,

    normalize_message: lambda do |msg|
      headers = call('headers_to_hash', msg.dig('payload', 'headers'))
      bodies  = call('extract_bodies', msg['payload'])
      {
        id: msg['id'],
        thread_id: msg['threadId'],
        history_id: msg['historyId'],
        label_ids: msg['labelIds'],
        snippet: msg['snippet'],
        size_estimate: msg['sizeEstimate'],
        internal_date: (msg['internalDate'] ? Time.at(msg['internalDate'].to_i / 1000).utc.iso8601 : nil),
        subject: headers['Subject'],
        from: headers['From'],
        to: headers['To'],
        cc: headers['Cc'],
        bcc: headers['Bcc'],
        date: headers['Date'],
        message_id_header: headers['Message-Id'],
        # Deep link directly to message
        web_link: (headers['Message-Id'].present? ? "https://mail.google.com/mail/u/0/#search/rfc822msgid%3A#{CGI.escape(headers['Message-Id'])}" : nil),
        body_text: bodies[:text],
        body_html: bodies[:html],
        payload: msg['payload']
      }
    end,

    # === MIME builders ===
    join_addr: lambda do |val|
      case val
      when nil then nil
      when String then val
      when Array then val.compact.reject(&:blank?).join(', ')
      else val.to_s
      end
    end,

    ensure_re: lambda do |subject|
      s = subject.to_s
      s =~ /\A\s*(re|sv|aw)\s*:/i ? s : "Re: #{s}"
    end,

    # Encode data URL or base64 or plain string to base64 (standard) for attachments
    to_b64: lambda do |content|
      str =
        if content.is_a?(String) && content.start_with?('data:')
          content.split(',', 2)[1].to_s # already base64
        else
          begin
            encode_base64(content.to_s)
          rescue
            [content.to_s].pack('m0')
          end
        end
      # strip CRLFs if any
      str.to_s.gsub(/\s+/, '')
    end,

    to_b64url: lambda do |raw|
      begin
        encode_urlsafe_base64(raw)
      rescue
        # Fallback: standard b64 then URL-safe transform (remove padding)
        b64 = [raw].pack('m0')
        b64.tr!('+/', '-_')
        b64.delete!('=')
        b64
      end
    end,

    b64url_to_b64: lambda do |b64url|
      return nil unless b64url
      s = b64url.tr('-_', '+/')
      s += '=' * ((4 - s.length % 4) % 4)
      s
    end,

    boundary: lambda do
      "----workato-#{(Time.now.to_f * 1000).to_i}-#{rand(36**8).to_s(36)}"
    end,

    fetch_attachment_bytes: lambda do |url|
      begin
        get(url).response_format_raw
      rescue
        nil
      end
    end,

    # Build RFC 2822 MIME; supports text, html, attachments, and custom headers.
    build_mime: lambda do |opts|
      from        = opts[:from]
      to          = call('join_addr', opts[:to])
      cc          = call('join_addr', opts[:cc])
      bcc         = call('join_addr', opts[:bcc])
      reply_to    = call('join_addr', opts[:reply_to])
      subject     = opts[:subject].to_s
      text_body   = opts[:text_body]
      html_body   = opts[:html_body]
      attachments = Array(opts[:attachments])
      extra_hdrs  = Array(opts[:headers]).map { |h| [h['name'], h['value']] }

      # Start headers
      lines = []
      lines << "From: #{from}" if from.present?
      lines << "To: #{to}" if to.present?
      lines << "Cc: #{cc}" if cc.present?
      lines << "Bcc: #{bcc}" if bcc.present?
      lines << "Reply-To: #{reply_to}" if reply_to.present?
      lines << "Subject: #{subject}"
      lines << "MIME-Version: 1.0"

      # In-Reply-To / References if provided by caller
      if opts[:in_reply_to].present?
        lines << "In-Reply-To: #{opts[:in_reply_to]}"
      end
      if opts[:references].present?
        refs = Array(opts[:references]).join(' ')
        lines << "References: #{refs}"
      end

      extra_hdrs.each { |name, value| lines << "#{name}: #{value}" }

      # Build body parts
      crlf = "\r\n"
      body = nil

      if attachments.present?
        # multipart/mixed
        mix_b = call('boundary')
        lines << "Content-Type: multipart/mixed; boundary=\"#{mix_b}\""
        body = []

        # Part 1: text/alternative (if both), else single text or html
        if text_body.present? && html_body.present?
          alt_b = call('boundary')
          body << "--#{mix_b}#{crlf}Content-Type: multipart/alternative; boundary=\"#{alt_b}\"#{crlf}#{crlf}" \
                  "--#{alt_b}#{crlf}Content-Type: text/plain; charset=\"UTF-8\"#{crlf}Content-Transfer-Encoding: 7bit#{crlf}#{crlf}#{text_body}#{crlf}" \
                  "--#{alt_b}#{crlf}Content-Type: text/html; charset=\"UTF-8\"#{crlf}Content-Transfer-Encoding: 7bit#{crlf}#{crlf}#{html_body}#{crlf}" \
                  "--#{alt_b}--#{crlf}"
        elsif html_body.present?
          body << "--#{mix_b}#{crlf}Content-Type: text/html; charset=\"UTF-8\"#{crlf}Content-Transfer-Encoding: 7bit#{crlf}#{crlf}#{html_body}#{crlf}"
        else
          body << "--#{mix_b}#{crlf}Content-Type: text/plain; charset=\"UTF-8\"#{crlf}Content-Transfer-Encoding: 7bit#{crlf}#{crlf}#{text_body.to_s}#{crlf}"
        end

        # Attachment parts
        attachments.each do |att|
          filename  = att['filename'] || att[:filename] || 'attachment.bin'
          mime_type = att['mime_type'] || att[:mime_type] || 'application/octet-stream'
          raw =
            if att['content'].present? || att[:content].present?
              (att['content'] || att[:content]).to_s
            elsif att['url'].present? || att[:url].present?
              call('fetch_attachment_bytes', (att['url'] || att[:url]).to_s) || ''
            else
              ''
            end
          encoded = call('to_b64', raw)
          body << "--#{mix_b}#{crlf}Content-Type: #{mime_type}; name=\"#{filename}\"#{crlf}" \
                  "Content-Transfer-Encoding: base64#{crlf}" \
                  "Content-Disposition: attachment; filename=\"#{filename}\"#{crlf}#{crlf}" \
                  "#{encoded}#{crlf}"
        end

        body << "--#{mix_b}--#{crlf}"
        body = body.join
      else
        # No attachments
        if text_body.present? && html_body.present?
          alt_b = call('boundary')
          lines << "Content-Type: multipart/alternative; boundary=\"#{alt_b}\""
          body = "--#{alt_b}#{crlf}Content-Type: text/plain; charset=\"UTF-8\"#{crlf}Content-Transfer-Encoding: 7bit#{crlf}#{crlf}#{text_body}#{crlf}" \
                 "--#{alt_b}#{crlf}Content-Type: text/html; charset=\"UTF-8\"#{crlf}Content-Transfer-Encoding: 7bit#{crlf}#{crlf}#{html_body}#{crlf}" \
                 "--#{alt_b}--#{crlf}"
        elsif html_body.present?
          lines << "Content-Type: text/html; charset=\"UTF-8\""
          lines << "Content-Transfer-Encoding: 7bit"
          body = html_body + crlf
        else
          lines << "Content-Type: text/plain; charset=\"UTF-8\""
          lines << "Content-Transfer-Encoding: 7bit"
          body = text_body.to_s + crlf
        end
      end

      (lines.join(crlf) + crlf + crlf + body.to_s)
    end,

    # === Reply preparation (fetches original if needed) ===
    prepare_reply: lambda do |connection, compose_mode, original_message_id, provided_subject|
      return { thread_id: nil, in_reply_to: nil, references: nil, subject: provided_subject } if compose_mode == 'new' || original_message_id.blank?

      if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
        subj = provided_subject.presence || call('ensure_re', "Mock subject")
        return { thread_id: "t_mock_#{original_message_id}", in_reply_to: "<#{original_message_id}@mock.local>", references: ["<#{original_message_id}@mock.local>"], subject: subj }
      end

      # Fetch only headers to reduce payload
      original = get("me/messages/#{original_message_id}")
                  .params(format: 'metadata', metadataHeaders: ['Subject', 'Message-Id', 'References'])
      hdrs = call('headers_to_hash', original.dig('payload', 'headers'))
      thread_id = original['threadId']
      msg_id    = hdrs['Message-Id']
      refs      = (hdrs['References'].to_s.split(/\s+/) + [msg_id]).compact.uniq
      subj      = provided_subject.presence || call('ensure_re', hdrs['Subject'].to_s)
      { thread_id: thread_id, in_reply_to: msg_id, references: refs, subject: subj }
    end,

    flatten_attachments_from_payload: lambda do |payload|
      results = []
      queue = [payload].compact
      while (part = queue.shift)
        part_id = part['partId']
        filename = part['filename']
        mime     = part['mimeType']
        body     = part['body'] || {}
        attach_id = body['attachmentId']
        size = body['size']
        h = call('headers_to_hash', part['headers'])
        content_id = h['Content-Id'] || h['Content-ID']
        content_disp = h['Content-Disposition']

        if attach_id.present? || filename.to_s.strip != ''
          results << {
            part_id: part_id,
            filename: filename,
            mime_type: mime,
            attachment_id: attach_id,
            size: size,
            content_id: content_id,
            content_disposition: content_disp,
            is_inline: (!!content_id || content_disp.to_s.downcase.include?('inline'))
          }
        end

        parts = part['parts']
        queue.concat(parts) if parts.is_a?(Array)
      end
      results
    end,

    # === Visual Gmail query ===
    quote_search_val: lambda do |val|
      s = val.to_s.strip
      if s =~ /[\s()]/
        escaped = s.gsub(/"/, '\"')
        "\"#{escaped}\""
      else
        s
      end
    end,

    build_gmail_query: lambda do |input|
      parts = []
      base = input['q'].to_s.strip
      parts << base unless base.blank?

      if input['from'].present?
        parts << "from:#{call('quote_search_val', input['from'])}"
      end
      if input['to'].present?
        parts << "to:#{call('quote_search_val', input['to'])}"
      end
      if input['subject'].present?
        parts << "subject:#{call('quote_search_val', input['subject'])}"
      end
      if input['category'].present?
        parts << "category:#{input['category']}"
      end
      parts << 'has:attachment' if input['has_attachment']
      parts << 'is:unread'      if input['unread_only']

      if input['newer_than_days'].present?
        parts << "newer_than:#{input['newer_than_days']}d"
      end
      if input['older_than_days'].present?
        parts << "older_than:#{input['older_than_days']}d"
      end

      if input['exclude_query'].present?
        parts << "-(#{input['exclude_query']})"
      end

      parts.compact.join(' ').squeeze(' ')
    end,

    # === Mock data ===
    mock_now_ms: -> { (Time.now.utc.to_f * 1000).to_i },

    mock_message: lambda do |connection, idx = 0, overrides = {}|
      seed = (connection['mock_seed'] || 'seed')
      base_ms = call('mock_now_ms') - (idx * 60_000)
      id = overrides[:id] || "m_#{base_ms}_#{idx}_#{seed.hash.abs % 1000}"
      subj = overrides[:subject] || "Mock subject ##{idx}"
      from = overrides[:from]    || 'Sender <sender@example.com>'
      to   = overrides[:to]      || (connection['mock_user_email'] || 'mock.user@example.com')
      {
        id: id,
        thread_id: "t_#{id}",
        history_id: "h_#{id}",
        label_ids: ['INBOX', (idx.even? ? 'UNREAD' : nil)].compact,
        snippet: "This is a mock snippet for #{subj}",
        size_estimate: 2048 + idx,
        internal_date: Time.at(base_ms / 1000).utc.iso8601,
        subject: subj,
        from: from,
        to: to,
        cc: nil,
        bcc: nil,
        date: Time.at(base_ms / 1000).utc.rfc2822,
        message_id_header: "<#{id}@mock.local>",
        body_text: "Hello from mock message ##{idx}.\nThis is test content.",
        body_html: "<p>Hello from <strong>mock</strong> message ##{idx}.</p>",
        payload: { mimeType: 'multipart/alternative', headers: [ { name: 'Subject', value: subj }, { name: 'Message-Id', value: "<#{id}@mock.local>" } ] }
      }
    end,

    mock_list: lambda do |connection, count = 3|
      { next_page_token: nil, items: (0..count).map { |i| call('mock_message', connection, i) } }
    end
  },

  object_definitions: {
    message_min: {
      fields: -> { [ { name: 'id' }, { name: 'thread_id' } ] }
    },

    message_full: {
      fields: -> {
        [
          { name: 'id' }, { name: 'thread_id' }, { name: 'history_id' },
          { name: 'label_ids', type: 'array', of: 'string' },
          { name: 'snippet' }, { name: 'size_estimate', type: 'integer' },
          { name: 'internal_date', type: 'date_time' },
          { name: 'subject' }, { name: 'from' }, { name: 'to' }, { name: 'cc' }, { name: 'bcc' }, { name: 'date' },
          { name: 'message_id_header' },
          { name: 'web_link' },
          { name: 'body_text' }, { name: 'body_html' },
          { name: 'payload', type: 'object' }
        ]
      }
    },

    message_min_list: {
      fields: ->(_connection, _config_fields, object_definitions) {
        [
          { name: 'next_page_token', label: 'Next page token' },
          { name: 'items', type: 'array', of: 'object', properties: object_definitions['message_min'] }
        ]
      }
    },

    label: {
      fields: -> {
        [
          { name: 'id' }, { name: 'name' },
          { name: 'messageListVisibility' }, { name: 'labelListVisibility' }, { name: 'type' },
          { name: 'color', type: 'object', properties: [ { name: 'backgroundColor' }, { name: 'textColor' } ]},
          { name: 'messagesTotal', type: 'integer' }, { name: 'messagesUnread', type: 'integer' },
          { name: 'threadsTotal', type: 'integer' }, { name: 'threadsUnread', type: 'integer' }
        ]
      }
    },

    draft: {
      fields: -> {
        [
          { name: 'id' },
          { name: 'message', type: 'object', properties: [
            { name: 'id' }, { name: 'threadId' }, { name: 'labelIds', type: 'array', of: 'string' },
            { name: 'snippet' }, { name: 'sizeEstimate', type: 'integer' }
          ]}
        ]
      }
    },

    attachment_out: {
      fields: -> {
        [
          { name: 'message_id' },
          { name: 'attachment_id' },
          { name: 'filename' },
          { name: 'size', type: 'integer' },
          { name: 'data_base64url', label: 'Data (base64url)' },
          { name: 'data_base64',    label: 'Data (base64 standard)' },
          { name: 'text_preview',   hint: 'If UTF-8 decodable and small' }
        ]
      }
    },

    attachment_meta: {
      fields: -> {
        [
          { name: 'message_id' },
          { name: 'part_id' },
          { name: 'attachment_id' },
          { name: 'filename' },
          { name: 'mime_type' },
          { name: 'size', type: 'integer' },
          { name: 'content_id' },
          { name: 'content_disposition' },
          { name: 'is_inline', type: 'boolean' }
        ]
      }
    },

    attachment_meta_list: {
      fields: ->(_c, _cfg, object_definitions) {
        [
          { name: 'items', type: 'array', of: 'object', properties: object_definitions['attachment_meta'] },
          { name: 'total_count', type: 'integer' }
        ]
      }
    }
  },

  pick_lists: {
    labels: lambda do |connection|
      if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
        [ ['INBOX', 'INBOX'], ['UNREAD', 'UNREAD'], ['STARRED', 'STARRED'] ]
      else
        get('me/labels')['labels']&.map { |l| [l['name'], l['id']] } || []
      end
    end
  },

  actions: {
    # ----- Test Helpers -----
    test_ping: {
      title: 'Test: ping/echo',
      input_fields: -> { [ { name: 'message', hint: 'Any text', optional: true } ] },
      execute: lambda do |connection, input|
        { mode: (connection['auth_type'] || 'gmail_oauth2'), message: input['message'] || 'pong', at: Time.now.utc.iso8601 }
      end,
      output_fields: -> { [ { name: 'mode' }, { name: 'message' }, { name: 'at' } ] }
    },
    test_generate_messages: {
      title: 'Test: generate mock messages',
      input_fields: -> { [ { name: 'count', type: 'integer', hint: 'Default 3', optional: true } ] },
      execute: lambda do |connection, input|
        items = (0...(input['count'] || 3).to_i).map { |i| call('mock_message', connection, i) }
        { next_page_token: nil, items: items.map { |m| { id: m[:id], thread_id: m[:thread_id] } } }
      end,
      output_fields: ->(object_definitions) { object_definitions['message_min_list'] }
    },

    # ----- Core Actions -----
    # (1) users.messages.list
    list_messages: {
      title: 'List messages',
      subtitle: 'users.messages.list',
      input_fields: -> {
        [
          { name: 'q', hint: 'Gmail search, e.g., from:alice newer_than:7d has:attachment', optional: true, label: "Query"  },
          { name: 'from',    hint: 'From email (exact or partial)', optional: true },
          { name: 'to',      hint: 'To email (exact or partial)', optional: true },
          { name: 'subject', hint: 'Subject contains', optional: true },
          { name: 'category', control_type: 'select', optional: true,
            options: [['Primary','primary'], ['Social','social'], ['Promotions','promotions'], ['Updates','updates'], ['Forums','forums']] },
          { name: 'has_attachment', type: 'boolean', control_type: 'checkbox', optional: true },
          { name: 'unread_only',    type: 'boolean', control_type: 'checkbox', optional: true },
          { name: 'newer_than_days', type: 'integer', hint: 'e.g., 7 → newer_than:7d', optional: true },
          { name: 'older_than_days', type: 'integer', hint: 'e.g., 30 → older_than:30d', optional: true },
          { name: 'exclude_query',   hint: 'e.g., category:promotions OR label:newsletters', optional: true },

          { name: 'label_ids', label: 'Filter by labels', type: 'array', of: 'string',
            control_type: 'multiselect', pick_list: 'labels', optional: true },
          { name: 'include_spam_trash', type: 'boolean', control_type: 'checkbox', optional: true },
          { name: 'max_results', type: 'integer', hint: '1–500 (Gmail default 100)', optional: true },
          { name: 'page_token', label: 'Page token', sticky: true, optional: true }
        ]
      },
        execute: lambda do |connection, input|
          if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
            items = (0...3).map { |i| m = call('mock_message', connection, i); { id: m[:id], thread_id: m[:thread_id] } }
            { next_page_token: nil, items: items }
          else
            compiled_q = call('build_gmail_query', input) # ← use helper
            resp = get('me/messages')
                    .params(
                      q: compiled_q,
                      labelIds: input['label_ids'],
                      includeSpamTrash: input['include_spam_trash'],
                      maxResults: (input['max_results'] || 20),
                      pageToken: input['page_token']
                    )
            {
              next_page_token: resp['nextPageToken'],
              items: Array(resp['messages']).map { |m| { id: m['id'], thread_id: m['threadId'] } }
            }
        end
      end,
      output_fields: ->(object_definitions) { object_definitions['message_min_list'] },
      sample_output: -> { { next_page_token: nil, items: [] } }
    },

    # (2) users.messages.get (format=full)
    get_message_full: {
      title: 'Get message (full parts)',
      subtitle: 'users.messages.get (format=full)',
      input_fields: -> { [ { name: 'message_id', optional: false, label: 'Message ID' } ] },
      execute: lambda do |connection, input|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          call('mock_message', connection, 0, id: input['message_id'])
        else
          msg = get("me/messages/#{input['message_id']}").params(format: 'full')
          call('normalize_message', msg)
        end
      end,
      output_fields: ->(object_definitions) { object_definitions['message_full'] }
    },

    # (3) users.messages.modify
    modify_message_labels: {
      title: 'Modify message labels',
      subtitle: 'users.messages.modify',
      help: ->(connection {
        msg = 'Requires scope `gmail.modify` (or `mail.google.com`).'
        unless connection['enabled_modify']
          msg += 'This connection does not have `gmail.modify` enabled.'
        end
        msg
      }),
      input_fields: -> {
        [
          { name: 'message_id', optional: false },
          { name: 'add_label_ids',    type: 'array', of: 'string', control_type: 'multiselect', pick_list: 'labels', optional: true },
          { name: 'remove_label_ids', type: 'array', of: 'string', control_type: 'multiselect', pick_list: 'labels', optional: true }
        ]
      },
      execute: lambda do |connection, input|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          add = Array(input['add_label_ids'])
          remove = Array(input['remove_label_ids'])
          { id: input['message_id'], labelIds: (['INBOX'] + add - remove).uniq, threadId: "t_#{input['message_id']}" }
        else
          post("me/messages/#{input['message_id']}/modify")
            .payload(addLabelIds: Array(input['add_label_ids']).presence, removeLabelIds: Array(input['remove_label_ids']).presence)
        end
      end,
      output_fields: -> { [ { name: 'id' }, { name: 'labelIds', type: 'array', of: 'string' }, { name: 'threadId' } ] }
    },

    # (4) users.drafts.create
    create_draft: {
      title: 'Create draft',
      subtitle: 'users.drafts.create',
      help: ->(connection) {
        msg = 'Builds RFC 2822 message and creates a draft. Use compose mode = reply/reply_all to target an existing thread. Requires gmail.send (or gmail.compose / mail.google.com).'
        unless (connection['enable_send'] || connection['enable_compose'])
          msg += ' ⚠️ Neither “Allow send” nor “Allow compose/drafts” is enabled in this connection.'
        end
        msg
      },
      input_fields: -> {
        [
          { name: 'compose_mode', control_type: 'select', options: [['New','new'], ['Reply','reply'], ['Reply all','reply_all']], default: 'new' },
          { name: 'original_message_id', hint: 'Gmail message ID to reply to (for reply/reply_all)', optional: true },
          { name: 'from', hint: 'Optional; must be a configured Send As alias', optional: true },
          { name: 'to', type: 'array', of: 'string', hint: 'List of recipients', optional: true },
          { name: 'cc', type: 'array', of: 'string', optional: true },
          { name: 'bcc', type: 'array', of: 'string', optional: true },
          { name: 'reply_to', type: 'array', of: 'string', optional: true },
          { name: 'subject', optional: true },
          { name: 'text_body', optional: true },
          { name: 'html_body', optional: true },
          { name: 'headers', type: 'array', of: 'object', properties: [ { name: 'name' }, { name: 'value' } ], optional: true },
          { name: 'attachments', type: 'array', of: 'object', optional: true, properties: [
              { name: 'filename' }, { name: 'mime_type' }, { name: 'content', hint: 'data: URI, base64, or raw text' }, { name: 'url', hint: 'If provided, connector will fetch bytes' }
            ] }
        ]
      },
      execute: lambda do |connection, input|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          m = call('mock_message', connection, 0, subject: input['subject'])
          { id: "d_#{m[:id]}", message: { id: m[:id], threadId: m[:thread_id], snippet: m[:snippet] } }
        else
          prep = call('prepare_reply', connection, input['compose_mode'], input['original_message_id'], input['subject'])
          mime = call('build_mime',
            from: input['from'],
            to: input['to'],
            cc: input['cc'],
            bcc: input['bcc'],
            reply_to: input['reply_to'],
            subject: prep[:subject],
            text_body: input['text_body'],
            html_body: input['html_body'],
            headers: input['headers'],
            in_reply_to: prep[:in_reply_to],
            references: prep[:references],
            attachments: input['attachments']
          )
          raw_b64url = call('to_b64url', mime)
          payload = { message: { raw: raw_b64url } }
          payload[:message][:threadId] = prep[:thread_id] if prep[:thread_id].present?
          post('me/drafts').payload(payload)
        end
      end,
      output_fields: ->(object_definitions) { object_definitions['draft'] }
    },

    # (5) users.messages.send
    send_message: {
      title: 'Send message (new / reply / reply-all)',
      subtitle: 'users.messages.send',
      help: ->(connection) {
        msg = 'Requires gmail.send (or gmail.compose / mail.google.com).'
        unless (connection['enable_send'] || connection['enable_compose'])
          msg += ' ⚠️ Neither “Allow send” nor “Allow compose/drafts” is enabled in this connection.'
        end
        msg
      },
      input_fields: -> {
        [
          { name: 'compose_mode', control_type: 'select', options: [['New','new'], ['Reply','reply'], ['Reply all','reply_all']], default: 'new' },
          { name: 'original_message_id', hint: 'Gmail message ID to reply to (for reply/reply_all)', optional: true },
          { name: 'from', hint: 'Optional; must be a configured Send As alias', optional: true },
          { name: 'to', type: 'array', of: 'string', optional: true },
          { name: 'cc', type: 'array', of: 'string', optional: true },
          { name: 'bcc', type: 'array', of: 'string', optional: true },
          { name: 'reply_to', type: 'array', of: 'string', optional: true },
          { name: 'subject', optional: true },
          { name: 'text_body', optional: true },
          { name: 'html_body', optional: true },
          { name: 'headers', type: 'array', of: 'object', properties: [ { name: 'name' }, { name: 'value' } ], optional: true },
          { name: 'attachments', type: 'array', of: 'object', optional: true, properties: [
              { name: 'filename' }, { name: 'mime_type' }, { name: 'content', hint: 'data: URI, base64, or raw text' }, { name: 'url', hint: 'If provided, connector will fetch bytes' }
            ] }
        ]
      },
      execute: lambda do |connection, input|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          m = call('mock_message', connection, 0, subject: input['subject'])
          { id: "sent_#{m[:id]}", threadId: m[:thread_id], labelIds: ['SENT'], snippet: m[:snippet] }
        else
          prep = call('prepare_reply', connection, input['compose_mode'], input['original_message_id'], input['subject'])
          mime = call('build_mime',
            from: input['from'],
            to: input['to'],
            cc: input['cc'],
            bcc: input['bcc'],
            reply_to: input['reply_to'],
            subject: prep[:subject],
            text_body: input['text_body'],
            html_body: input['html_body'],
            headers: input['headers'],
            in_reply_to: prep[:in_reply_to],
            references: prep[:references],
            attachments: input['attachments']
          )
          raw_b64url = call('to_b64url', mime)
          body = { raw: raw_b64url }
          body[:threadId] = prep[:thread_id] if prep[:thread_id].present?
          post('me/messages/send').payload(body)
        end
      end,
      output_fields: -> { [ { name: 'id' }, { name: 'threadId' }, { name: 'labelIds', type: 'array', of: 'string' }, { name: 'snippet' } ] }
    },

    # (6) users.labels.list
    list_labels: {
      title: 'List labels',
      subtitle: 'users.labels.list',
      execute: lambda do |connection|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          { items: [ { id: 'INBOX', name: 'INBOX', type: 'system' }, { id: 'UNREAD', name: 'UNREAD', type: 'system' }, { id: 'STARRED', name: 'STARRED', type: 'system' } ] }
        else
          { items: get('me/labels')['labels'] }
        end
      end,
      output_fields: ->(object_definitions) { [ { name: 'items', type: 'array', of: 'object', properties: object_definitions['label'] } ] }
    },

    # (7) users.labels.create
    create_label: {
      title: 'Create label',
      subtitle: 'users.labels.create',    
      help: ->(connection) {
        msg = 'Requires gmail.labels or gmail.modify (or mail.google.com).'
        unless (connection['enable_labels'] || connection['enable_modify'])
          msg += ' ⚠️ This connection currently lacks label permissions.'
        end
        msg
      },
      input_fields: -> {
        [
          { name: 'name', optional: false },
          { name: 'labelListVisibility', control_type: 'select', options: [['labelShow', 'labelShow'], ['labelShowIfUnread', 'labelShowIfUnread'], ['labelHide', 'labelHide']], optional: true },
          { name: 'messageListVisibility', control_type: 'select', options: [['show', 'show'], ['hide', 'hide']], optional: true },
          { name: 'color', type: 'object', optional: true, properties: [
            { name: 'backgroundColor', hint: '#RRGGBB' },
            { name: 'textColor', hint: '#RRGGBB' }
          ] }
        ]
      },
      execute: lambda do |connection, input|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          { id: "Label_#{Time.now.to_i}", name: input['name'], type: 'user', labelListVisibility: (input['labelListVisibility'] || 'labelShow'), messageListVisibility: (input['messageListVisibility'] || 'show') }
        else
          post('me/labels').payload(input)
        end
      end,
      output_fields: ->(object_definitions) { object_definitions['label'] }
    },

    # 8) users.messages.attachments.get
    get_attachment: {
      title: 'Get attachment',
      subtitle: 'users.messages.attachments.get',
      help: 'Fetches attachment bytes by attachmentId. Returns both base64url (as returned by Gmail) and standard base64 for convenience.',
      input_fields: -> {
        [
          { name: 'message_id', optional: false, label: 'Message ID' },
          { name: 'attachment_id', optional: false, label: 'Attachment ID' },
          { name: 'filename', optional: true, hint: 'Optional filename for downstream use' }
        ]
      },
      execute: lambda do |connection, input|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          mock_data = "This is a mock attachment for #{input['attachment_id']}"
          b64 = [mock_data].pack('m0')
          b64url = b64.tr('+/', '-_').delete('=')
          { message_id: input['message_id'], attachment_id: input['attachment_id'], filename: (input['filename'] || 'mock.txt'), size: mock_data.bytesize, data_base64url: b64url, data_base64: b64, text_preview: mock_data }
        else
          att = get("me/messages/#{input['message_id']}/attachments/#{input['attachment_id']}")
          b64url = att['data']
          b64 = call('b64url_to_b64', b64url)
          preview = nil
          begin
            raw = decode_urlsafe_base64(b64url)
            if raw.bytesize <= 4096
              s = raw.dup
              s.force_encoding('UTF-8')
              preview = s.valid_encoding? ? s : nil
            end
          rescue
          end
          { message_id: input['message_id'], attachment_id: input['attachment_id'], filename: input['filename'], size: att['size'], data_base64url: b64url, data_base64: b64, text_preview: preview }
        end
      end,
      output_fields: ->(object_definitions) { object_definitions['attachment_out'] }
    },

    # (9) users.drafts.send
    send_draft: {
      title: 'Send draft',
      subtitle: 'users.drafts.send',
      help: 'Sends an existing draft by draft ID. Requires gmail.send or gmail.compose.',
      input_fields: -> { [ { name: 'draft_id', optional: false } ] },
      execute: lambda do |connection, input|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          { id: "sent_from_#{input['draft_id']}", threadId: "t_#{input['draft_id']}", labelIds: ['SENT'], snippet: 'Mock draft sent.' }
        else
          post('me/drafts/send').payload(id: input['draft_id'])
        end
      end,
      output_fields: -> { [ { name: 'id' }, { name: 'threadId' }, { name: 'labelIds', type: 'array', of: 'string' }, { name: 'snippet' } ] }
    },

    # (10) enumerate attachments - helper
    list_message_attachments: {
      title: 'List message attachments (metadata)',
      subtitle: 'Helper: enumerate filename/mime/attachments',
      input_fields: -> {
        [
          { name: 'message_id', optional: false, label: 'Message ID' },
          { name: 'include_inline', type: 'boolean', control_type: 'checkbox', hint: 'Include inline parts (Content-ID/inline)', optional: true }
        ]
      },
      execute: lambda do |connection, input|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          items = [
            { message_id: input['message_id'], part_id: '2', attachment_id: 'att_mock_pdf', filename: 'spec.pdf',  mime_type: 'application/pdf', size: 1024, content_disposition: 'attachment; filename="spec.pdf"', is_inline: false },
            { message_id: input['message_id'], part_id: '3', attachment_id: 'att_mock_png', filename: 'logo.png', mime_type: 'image/png',       size: 512,  content_id: '<logo@mock>', content_disposition: 'inline; filename="logo.png"', is_inline: true }
          ]
          items = items.reject { |i| i[:is_inline] } unless input['include_inline']
          { items: items, total_count: items.length }
        else
          msg = get("me/messages/#{input['message_id']}").params(format: 'full')
          attachments = call('flatten_attachments_from_payload', msg['payload'])
          attachments = attachments.reject { |i| i[:is_inline] } unless input['include_inline']
          items = attachments.map { |a| a.merge(message_id: input['message_id']) }
          { items: items, total_count: items.length }
        end
      end,
      output_fields: ->(object_definitions) { object_definitions['attachment_meta_list'] }
    }
  },

  triggers: {
    new_message: {
      title: 'New message (polling)',
      subtitle: 'Use Gmail query/labels or mock data',

      input_fields: lambda do
        [
          # Type a raw Gmail query for 'q' parm
          { name: 'q', hint: 'e.g., in:inbox -category:promotions', optional: true },

          # Visual query builder helpers (optional)
          { name: 'from',    hint: 'From email (exact or partial)', optional: true },
          { name: 'to',      hint: 'To email (exact or partial)', optional: true },
          { name: 'subject', hint: 'Subject contains', optional: true },
          { name: 'category', control_type: 'select', optional: true,
            options: [['Primary','primary'], ['Social','social'], ['Promotions','promotions'], ['Updates','updates'], ['Forums','forums']] },
          { name: 'has_attachment', type: 'boolean', control_type: 'checkbox', optional: true },
          { name: 'unread_only',    type: 'boolean', control_type: 'checkbox', optional: true },
          { name: 'newer_than_days', type: 'integer', hint: 'e.g., 7 → newer_than:7d', optional: true },
          { name: 'older_than_days', type: 'integer', hint: 'e.g., 30 → older_than:30d', optional: true },
          { name: 'exclude_query',   hint: 'Exclude patterns, e.g., category:promotions OR label:newsletters', optional: true },

          # Existing filters
          { name: 'label_ids', label: 'Filter by labels', type: 'array', of: 'string',
            control_type: 'multiselect', pick_list: 'labels', optional: true },
          { name: 'since', label: 'Start from (ISO8601)', type: 'date_time', optional: true },
          { name: 'include_spam_trash', type: 'boolean', control_type: 'checkbox', label: 'Include Spam/Trash', optional: true },
          { name: 'page_size', type: 'integer', hint: '1–500 (default 100)', optional: true }
        ]
      end,

      poll: lambda do |connection, input, closure|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          events = (0...3).map { |i| call('mock_message', connection, i) }
          { events: events, next_poll: call('mock_now_ms'), can_poll_more: false }
        else
          start_ms =
            if closure.present?
              closure.to_i
            elsif input['since'].present?
              (input['since'].to_time.to_i * 1000)
            else
              ((Time.now.utc.to_i - 3600) * 1000)
            end
          after_seconds = start_ms / 1000

          base_q = call('build_gmail_query', input)
          q = [base_q, "after:#{after_seconds}"].reject(&:blank?).join(' ').strip

          list = get('me/messages')
                  .params(
                    q: q,
                    labelIds: input['label_ids'],
                    includeSpamTrash: input['include_spam_trash'],
                    maxResults: (input['page_size'] || 100)
                  )

          ids = Array(list['messages']).map { |m| m['id'] }
          events = []
          unless ids.blank?
            events = ids.map { |id| call('normalize_message', get("me/messages/#{id}").params(format: 'full')) }
            max_ms = events.compact.map { |e| e['internal_date'] }.compact.map { |t| Time.parse(t).to_i * 1000 }.max
            closure = max_ms if max_ms
          end

          { events: events, next_poll: closure, can_poll_more: false }
        end
      end,

      dedup: ->(record) { "#{record['id']}@#{record['internal_date']}" },
      output_fields: ->(object_definitions, _connection, _config) { object_definitions['message_full'] },
      sample_output: -> { {} }
    }
  }
}
