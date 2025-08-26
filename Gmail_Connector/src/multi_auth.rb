{
  title: 'Gmail (OAuth + Mock)',

  connection: {
    # 1) Choose auth mode at connection time
    fields: [
      {
        name: 'auth_type',
        label: 'Authentication mode',
        control_type: 'select',
        # Use `options` for connection fields (pick_lists aren’t available here)
        options: [
          ['Gmail OAuth (live)', 'gmail_oauth2'],
          ['Mock (no auth)', 'mock']
        ],
        default: 'gmail_oauth2',
        extends_schema: true
      }
    ],

    # 2) Multi-auth: choose an auth flow by key via `selected`; define flows in `options`
    authorization: {
      type: 'multi',

      selected: lambda do |connection|
        connection['auth_type'] || 'gmail_oauth2'
      end,

      options: {
        # ---- Live Gmail OAuth2 flow ----
        gmail_oauth2: {
          type: 'oauth2',

          fields: [
            { name: 'client_id', optional: false, hint: 'Google Cloud OAuth 2.0 Client ID' },
            { name: 'client_secret', control_type: 'password', optional: false, hint: 'Google Cloud OAuth 2.0 Client Secret' },

            # Scope toggles (least-privilege default)
            {
              name: 'enable_modify',
              label: 'Allow modify (gmail.modify)',
              type: 'boolean',
              control_type: 'checkbox',
              optional: true
            },
            {
              name: 'enable_send',
              label: 'Allow sending (gmail.send)',
              type: 'boolean',
              control_type: 'checkbox',
              optional: true
            }
          ],

          authorization_url: lambda do |connection|
            scopes = [
              'https://www.googleapis.com/auth/gmail.readonly',
              'https://www.googleapis.com/auth/gmail.metadata'
            ]
            scopes << 'https://www.googleapis.com/auth/gmail.modify' if connection['enable_modify']
            scopes << 'https://www.googleapis.com/auth/gmail.send'   if connection['enable_send']

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
            response = post('https://oauth2.googleapis.com/token')
                        .payload(
                          grant_type: 'refresh_token',
                          refresh_token: refresh_token,
                          client_id: connection['client_id'],
                          client_secret: connection['client_secret']
                        )
                        .request_format_www_form_urlencoded
            { access_token: response['access_token'], refresh_token: response['refresh_token'] }
          end
        },

        # ---- Mock flow (no external auth) ----
        mock: {
          type: 'custom_auth',

          fields: [
            { name: 'mock_user_email', label: 'Mock user email', default: 'mock.user@example.com', optional: true },
            { name: 'mock_seed', label: 'Mock seed (optional)', hint: 'Any string to vary the sample data', optional: true }
          ],

          # Add a header for clarity in logs; no token required
          apply: ->(_connection) { headers('X-Mock': 'true') }
        }
      }
    },

    # 3) Base URI can be dynamic by auth mode
    base_uri: lambda do |connection|
      if (connection['auth_type'] || 'gmail_oauth2') == 'gmail_oauth2'
        'https://gmail.googleapis.com/gmail/v1/users'
      else
        # Not used, but set to a non-routable host by convention
        'https://mock.local/unused'
      end
    end
  },

  # 4) Connection test for both modes
  test: lambda do |connection|
    if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
      # Succeed without HTTP in mock mode
      { ok: true, email: (connection['mock_user_email'] || 'mock.user@example.com') }
    else
      # Gmail: confirms auth and quota
      get('me/profile')
    end
  end,

  # ---------- Helper methods ----------
  methods: {
    headers_to_hash: lambda do |headers_array|
      (headers_array || []).each_with_object({}) { |h, memo| memo[h['name']] = h['value'] }
    end,

    extract_bodies: lambda do |payload|
      out = { text: nil, html: nil }
      queue = [payload].compact
      while (part = queue.shift)
        mime = part['mimeType']
        data = (part.dig('body', 'data'))
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
        body_text: bodies[:text],
        body_html: bodies[:html]
      }
    end,

    # -------- Mock data helpers --------
    mock_now_ms: -> { (Time.now.utc.to_f * 1000).to_i },

    mock_message: lambda do |connection, idx = 0, overrides = {}|
      seed = (connection['mock_seed'] || 'seed')
      base_ms = call('mock_now_ms') - (idx * 60_000)
      id = "m_#{base_ms}_#{idx}_#{seed.hash.abs % 1000}"
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
        body_html: "<p>Hello from <strong>mock</strong> message ##{idx}.</p>"
      }
    end,

    mock_list: lambda do |connection, count = 3|
      { next_page_token: nil, items: (0...count).map { |i| call('mock_message', connection, i) } }
    end
  },

  # ---------- Schemas ----------
  object_definitions: {
    message: {
      fields: lambda do
        [
          { name: 'id' },
          { name: 'thread_id' },
          { name: 'history_id' },
          { name: 'label_ids', type: 'array', of: 'string' },
          { name: 'snippet' },
          { name: 'size_estimate', type: 'integer' },
          { name: 'internal_date', type: 'date_time' },
          { name: 'subject' },
          { name: 'from' },
          { name: 'to' },
          { name: 'cc' },
          { name: 'bcc' },
          { name: 'date' },
          { name: 'message_id_header' },
          { name: 'body_text' },
          { name: 'body_html' }
        ]
      end
    },

    message_list: {
      fields: lambda do |_connection, _config_fields, object_definitions|
        [
          { name: 'next_page_token', label: 'Next page token' },
          { name: 'items', type: 'array', of: 'object', properties: object_definitions['message'] }
        ]
      end
    },

    label: {
      fields: lambda do
        [
          { name: 'id' }, { name: 'name' },
          { name: 'messageListVisibility' }, { name: 'labelListVisibility' }, { name: 'type' },
          { name: 'color', type: 'object', properties: [ { name: 'backgroundColor' }, { name: 'textColor' } ]},
          { name: 'messagesTotal', type: 'integer' }, { name: 'messagesUnread', type: 'integer' },
          { name: 'threadsTotal', type: 'integer' }, { name: 'threadsUnread', type: 'integer' }
        ]
      end
    }
  },

  # ---------- Pick lists ----------
  pick_lists: {
    labels: lambda do |connection|
      if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
        [ ['INBOX', 'INBOX'], ['UNREAD', 'UNREAD'], ['STARRED', 'STARRED'] ]
      else
        get('me/labels')['labels']&.map { |l| [l['name'], l['id']] } || []
      end
    end
  },

  # ---------- Actions ----------
  actions: {
    # Simple test action to validate recipes in mock/live
    test_ping: {
      title: 'Test: ping/echo',
      input_fields: -> { [ { name: 'message', hint: 'Any text', optional: true } ] },
      execute: lambda do |connection, input|
        {
          mode: (connection['auth_type'] || 'gmail_oauth2'),
          message: input['message'] || 'pong',
          at: Time.now.utc.iso8601
        }
      end,
      output_fields: -> { [ { name: 'mode' }, { name: 'message' }, { name: 'at' } ] }
    },

    # Produce mock messages regardless of Gmail availability
    test_generate_messages: {
      title: 'Test: generate mock messages',
      input_fields: -> { [ { name: 'count', type: 'integer', hint: 'Default 3', optional: true } ] },
      execute: lambda do |connection, input|
        call('mock_list', connection, (input['count'] || 3).to_i)
      end,
      output_fields: lambda do |object_definitions, _connection, _config|
        object_definitions['message_list']
      end
    },

    search_messages: {
      title: 'Search messages',
      subtitle: 'Gmail `q` syntax + optional labels',

      input_fields: lambda do
        [
          { name: 'q', hint: 'e.g., from:alice newer_than:7d has:attachment', optional: true },
          { name: 'label_ids', label: 'Filter by labels', type: 'array', of: 'string', control_type: 'multiselect', pick_list: 'labels', optional: true },
          { name: 'include_spam_trash', type: 'boolean', control_type: 'checkbox', label: 'Include Spam/Trash', optional: true },
          { name: 'max_results', type: 'integer', hint: '1–500 (Gmail defaults to 100)', optional: true },
          { name: 'page_token', label: 'Page token', sticky: true, optional: true },
          {
            name: 'format',
            control_type: 'select',
            options: [
              ['full (headers+bodies)', 'full'],
              ['metadata (headers only)', 'metadata'],
              ['minimal (ids+thread)', 'minimal']
            ],
            optional: true
          },
          { name: 'metadata_headers', type: 'array', of: 'string', optional: true }
        ]
      end,

      execute: lambda do |connection, input|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          call('mock_list', connection, 3)
        else
          resp = get('me/messages')
                  .params(
                    q: input['q'],
                    labelIds: input['label_ids'],
                    includeSpamTrash: input['include_spam_trash'],
                    maxResults: (input['max_results'] || 20),
                    pageToken: input['page_token']
                  )
          ids = Array(resp['messages']).map { |m| m['id'] }
          return { next_page_token: resp['nextPageToken'], items: [] } if ids.blank?

          fmt = (input['format'].presence || 'full')
          items = ids.map do |id|
            detail = get("me/messages/#{id}").params(format: fmt, metadataHeaders: input['metadata_headers'])
            call('normalize_message', detail)
          end
          { next_page_token: resp['nextPageToken'], items: items }
        end
      end,

      output_fields: lambda do |object_definitions, _connection, _config|
        object_definitions['message_list']
      end,

      sample_output: -> { { next_page_token: nil, items: [] } }
    },

    get_message: {
      title: 'Get message',
      input_fields: lambda do
        [
          { name: 'message_id', optional: false },
          {
            name: 'format',
            control_type: 'select',
            options: [
              ['full (headers+bodies)', 'full'],
              ['metadata (headers only)', 'metadata'],
              ['minimal (ids+thread)', 'minimal'],
              ['raw (base64 URL-safe)', 'raw']
            ],
            optional: true
          },
          { name: 'metadata_headers', type: 'array', of: 'string', optional: true }
        ]
      end,

      execute: lambda do |connection, input|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          call('mock_message', connection, 0, id: input['message_id'])
        else
          fmt = (input['format'].presence || 'full')
          msg = get("me/messages/#{input['message_id']}").params(format: fmt, metadataHeaders: input['metadata_headers'])
          fmt == 'raw' ? { id: msg['id'], raw: msg['raw'], thread_id: msg['threadId'] } : call('normalize_message', msg)
        end
      end,

      output_fields: lambda do |_object_definitions, _connection, _config|
        [
          { name: 'id' }, { name: 'thread_id' }, { name: 'raw' },
          { name: 'subject' }, { name: 'from' }, { name: 'to' }, { name: 'cc' }, { name: 'bcc' }, { name: 'date' },
          { name: 'label_ids', type: 'array', of: 'string' }, { name: 'internal_date', type: 'date_time' },
          { name: 'snippet' }, { name: 'body_text' }, { name: 'body_html' }
        ]
      end
    },

    list_labels: {
      title: 'List labels',
      execute: lambda do |connection|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          { items: [ { id: 'INBOX', name: 'INBOX' }, { id: 'UNREAD', name: 'UNREAD' }, { id: 'STARRED', name: 'STARRED' } ] }
        else
          { items: get('me/labels')['labels'] }
        end
      end,
      output_fields: lambda do |object_definitions, _connection, _config|
        [ { name: 'items', type: 'array', of: 'object', properties: object_definitions['label'] } ]
      end,
      sample_output: -> { { items: [] } }
    },

    modify_message: {
      title: 'Modify message (labels / read state)',
      help: 'Requires gmail.modify scope (enable on the connection).',
      input_fields: lambda do
        [
          { name: 'message_id', optional: false },
          { name: 'add_label_ids', type: 'array', of: 'string', control_type: 'multiselect', pick_list: 'labels', optional: true },
          { name: 'remove_label_ids', type: 'array', of: 'string', control_type: 'multiselect', pick_list: 'labels', optional: true },
          { name: 'mark_as_read', type: 'boolean', control_type: 'checkbox', hint: 'Removes the UNREAD label' }
        ]
      end,

      execute: lambda do |connection, input|
        if (connection['auth_type'] || 'gmail_oauth2') == 'mock'
          # Simulate label changes
          add = Array(input['add_label_ids'])
          remove = Array(input['remove_label_ids'])
          remove << 'UNREAD' if input['mark_as_read']
          { id: input['message_id'], labelIds: (['INBOX'] + add - remove).uniq, threadId: "t_#{input['message_id']}" }
        else
          add = Array(input['add_label_ids']).dup
          remove = Array(input['remove_label_ids']).dup
          remove << 'UNREAD' if input['mark_as_read']
          post("me/messages/#{input['message_id']}/modify")
            .payload(addLabelIds: add.presence, removeLabelIds: remove.presence)
        end
      end,

      output_fields: -> { [ { name: 'id' }, { name: 'labelIds', type: 'array', of: 'string' }, { name: 'threadId' } ] }
    }
  },

  # ---------- Triggers ----------
  triggers: {
    new_message: {
      title: 'New message (polling)',
      subtitle: 'Use Gmail query/labels or mock data',

      input_fields: lambda do
        [
          { name: 'q', hint: 'e.g., in:inbox -category:promotions', optional: true },
          { name: 'label_ids', label: 'Filter by labels', type: 'array', of: 'string', control_type: 'multiselect', pick_list: 'labels', optional: true },
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

          q_parts = []
          q_parts << input['q'] if input['q'].present?
          q_parts << "after:#{after_seconds}"
          q = q_parts.compact.join(' ').strip

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
      output_fields: ->(object_definitions, _connection, _config) { object_definitions['message'] },
      sample_output: -> { {} }
    }
  }
}
