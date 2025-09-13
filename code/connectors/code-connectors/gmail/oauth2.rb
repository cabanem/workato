{
  title: 'Gmail (Custom OAuth 2.0)',

  connection: {
    fields: [
      { name: 'client_id', optional: false, hint: 'Google Cloud OAuth 2.0 Client ID' },
      { name: 'client_secret', control_type: 'password', optional: false, hint: 'Google Cloud OAuth 2.0 Client Secret' },

      # Opt-in scope toggles (least-privilege by default)
      {
        name: 'enable_modify',
        label: 'Allow modify (gmail.modify)',
        type: 'boolean',
        control_type: 'checkbox',
        optional: true,
        hint: 'Enable to add/remove labels or mark read/unread.'
      },
      {
        name: 'enable_send',
        label: 'Allow sending email (gmail.send)',
        type: 'boolean',
        control_type: 'checkbox',
        optional: true,
        hint: 'Enable to send new emails or replies.'
      }
    ],

    authorization: {
      type: 'oauth2',

      # Workato appends redirect_uri/state for you. You must supply response_type=code and scopes.
      authorization_url: lambda do |connection|
        scopes = [
          'https://www.googleapis.com/auth/gmail.readonly', # read bodies + metadata
          'https://www.googleapis.com/auth/gmail.metadata'  # headers/labels/history (no bodies)
        ]
        scopes << 'https://www.googleapis.com/auth/gmail.modify' if connection['enable_modify']
        scopes << 'https://www.googleapis.com/auth/gmail.send'   if connection['enable_send']

        # Google endpoints & params: response_type=code, access_type=offline, prompt=consent, include_granted_scopes=true
        "https://accounts.google.com/o/oauth2/v2/auth" \
          "?response_type=code" \
          "&access_type=offline" \
          "&prompt=consent" \
          "&include_granted_scopes=true" \
          "&scope=#{CGI.escape(scopes.uniq.join(' '))}"
      end,

      token_url: lambda do
        'https://oauth2.googleapis.com/token'
      end,

      client_id: lambda do |connection|
        connection['client_id']
      end,

      client_secret: lambda do |connection|
        connection['client_secret']
      end,

      # Attach the access token to every request
      apply: lambda do |_connection, access_token|
        headers('Authorization': "Bearer #{access_token}")
      end,

      # Refresh behavior (Workato manages refresh tokens; this tells it how to refresh on 401/403)
      refresh_on: [401, 403],
      refresh: lambda do |connection, refresh_token|
        response =
          post('https://oauth2.googleapis.com/token').
            payload(
              grant_type: 'refresh_token',
              refresh_token: refresh_token,
              client_id: connection['client_id'],
              client_secret: connection['client_secret']
            ).
            request_format_www_form_urlencoded

        {
          access_token: response['access_token'],
          refresh_token: response['refresh_token']
        }
      end
    },

    base_uri: lambda do
      # So we can GET 'me/...' later
      'https://gmail.googleapis.com/gmail/v1/users'
    end,

    # Verifies auth: returns profile for authenticated user
    test: lambda do |_connection|
      get('me/profile')
    end
  },

  # ---------- Reusable helpers ----------
  methods: {
    # Convert Gmail headers array into a simple hash
    headers_to_hash: lambda do |headers_array|
      (headers_array || []).each_with_object({}) do |h, memo|
        memo[h['name']] = h['value']
      end
    end,

    # Recursively extract 'text/plain' and 'text/html' parts from payload
    extract_bodies: lambda do |payload|
      out = { text: nil, html: nil }
      queue = [payload].compact
      while (part = queue.shift)
        mime = part['mimeType']
        body = (part['body'] || {})
        data = body['data']
        if data.present?
          begin
            # Workato SDK provides decode_urlsafe_base64; Gmail uses URL-safe base64
            content = decode_urlsafe_base64(data)
          rescue
            # Fallback: do not crash on bad encodings
            content = nil
          end
          if mime == 'text/plain'
            out[:text] ||= content
          elsif mime == 'text/html'
            out[:html] ||= content
          end
        end
        parts = part['parts']
        queue.concat(parts) if parts.is_a?(Array)
      end
      out
    end,

    # Normalize a Gmail message into a convenient shape
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
    end
  },

  # ---------- Schemas ----------
  object_definitions: {
    message: {
      fields: lambda do |_connection, _config_fields, _object_defs|
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
          {
            name: 'items',
            type: 'array', of: 'object',
            properties: object_definitions['message']
          }
        ]
      end
    },

    label: {
      fields: lambda do
        [
          { name: 'id' },
          { name: 'name' },
          { name: 'messageListVisibility' },
          { name: 'labelListVisibility' },
          { name: 'type' },
          { name: 'color', type: 'object', properties: [
            { name: 'backgroundColor' },
            { name: 'textColor' }
          ]},
          { name: 'messagesTotal', type: 'integer' },
          { name: 'messagesUnread', type: 'integer' },
          { name: 'threadsTotal', type: 'integer' },
          { name: 'threadsUnread', type: 'integer' }
        ]
      end
    }
  },

  # ---------- Picklists ----------
  pick_lists: {
    labels: lambda do |_connection|
      get('me/labels')['labels']&.map { |l| [l['name'], l['id']] } || []
    end
  },

  # ---------- Actions ----------
  actions: {

    # List/Search messages (Gmail supports the 'q' parameter)
    search_messages: {
      title: 'Search messages',
      subtitle: 'Use Gmail query syntax + optional label filters',
      help: lambda do |_input, _labels|
        'The `q` parameter supports most Gmail search operators, e.g. ' \
        '`from:alice@example.com subject:(invoice) has:attachment newer_than:7d -in:trash`.' \
        ' Combine with Label filters when needed.'
      end,

      input_fields: lambda do |_object_defs, _connection, _config|
        [
          {
            name: 'q',
            hint: 'Gmail search (e.g., from:alice newer_than:7d has:attachment)',
            optional: true
          },
          {
            name: 'label_ids',
            label: 'Filter by labels',
            type: 'array', of: 'string',
            control_type: 'multiselect',
            pick_list: 'labels',
            optional: true
          },
          { name: 'include_spam_trash', type: 'boolean', control_type: 'checkbox', label: 'Include Spam/Trash', optional: true },
          { name: 'max_results', type: 'integer', hint: '1–500 (Gmail defaults to 100)', optional: true },
          { name: 'page_token', label: 'Page token', sticky: true, optional: true },

          # Advanced:
          {
            name: 'format',
            control_type: 'select',
            pick_list: [
              ['full (headers+bodies)', 'full'],
              ['metadata (headers only)', 'metadata'],
              ['minimal (ids+thread)', 'minimal']
            ],
            optional: true,
            hint: 'How to fetch each message after listing (default: full).'
          },
          {
            name: 'metadata_headers',
            type: 'array', of: 'string', optional: true,
            hint: 'Only when format=metadata; e.g. Subject,From,To,Date'
          }
        ]
      end,

      execute: lambda do |_connection, input|
        # First call: list message IDs matching q/labels
        resp = get('me/messages').
                 params(
                   q: input['q'],
                   labelIds: input['label_ids'],
                   includeSpamTrash: input['include_spam_trash'],
                   maxResults: (input['max_results'] || 20),
                   pageToken: input['page_token']
                 )

        ids = Array(resp['messages']).map { |m| m['id'] }
        return { next_page_token: resp['nextPageToken'], items: [] } if ids.blank?

        fmt = (input['format'].presence || 'full')

        # Fetch each message detail; for metadata, optionally request specific headers
        items = ids.map do |id|
          detail = get("me/messages/#{id}").
                     params(
                       format: fmt,
                       metadataHeaders: input['metadata_headers']
                     )
          call('normalize_message', detail)
        end

        {
          next_page_token: resp['nextPageToken'],
          items: items
        }
      end,

      output_fields: lambda do |object_definitions, _connection, _config|
        object_definitions['message_list']
      end,

      sample_output: lambda do
        { next_page_token: nil, items: [] }
      end
    },

    # Get one message by id
    get_message: {
      title: 'Get message',
      input_fields: lambda do
        [
          { name: 'message_id', optional: false },
          {
            name: 'format',
            control_type: 'select',
            pick_list: [
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

      execute: lambda do |_connection, input|
        fmt = (input['format'].presence || 'full')
        msg = get("me/messages/#{input['message_id']}").
                params(format: fmt, metadataHeaders: input['metadata_headers'])

        if fmt == 'raw'
          # Keep raw for downstream processing; do not decode by default
          { id: msg['id'], raw: msg['raw'], thread_id: msg['threadId'] }
        else
          call('normalize_message', msg)
        end
      end,

      output_fields: lambda do |_object_definitions, _connection, _config|
        [
          { name: 'id' },
          { name: 'thread_id' },
          { name: 'raw' },
          { name: 'subject' },
          { name: 'from' },
          { name: 'to' },
          { name: 'cc' },
          { name: 'bcc' },
          { name: 'date' },
          { name: 'label_ids', type: 'array', of: 'string' },
          { name: 'internal_date', type: 'date_time' },
          { name: 'snippet' },
          { name: 'body_text' },
          { name: 'body_html' }
        ]
      end
    },

    # List labels (handy for building recipes)
    list_labels: {
      title: 'List labels',
      execute: lambda do
        { items: get('me/labels')['labels'] }
      end,
      output_fields: lambda do |object_definitions, _connection, _config|
        [
          { name: 'items', type: 'array', of: 'object', properties: object_definitions['label'] }
        ]
      end,
      sample_output: lambda do
        { items: [] }
      end
    },

    # Modify labels / mark read-unread (requires gmail.modify scope)
    modify_message: {
      title: 'Modify message (labels / read state)',
      help: 'Requires the connection to be created with the gmail.modify scope enabled.',
      input_fields: lambda do |_object_defs, _connection, _config|
        [
          { name: 'message_id', optional: false },
          { name: 'add_label_ids', type: 'array', of: 'string', control_type: 'multiselect', pick_list: 'labels', optional: true },
          { name: 'remove_label_ids', type: 'array', of: 'string', control_type: 'multiselect', pick_list: 'labels', optional: true },
          {
            name: 'mark_as_read',
            type: 'boolean',
            control_type: 'checkbox',
            hint: 'Convenience: translates to removing the UNREAD label'
          }
        ]
      end,

      execute: lambda do |_connection, input|
        add = Array(input['add_label_ids']).dup
        remove = Array(input['remove_label_ids']).dup

        if input['mark_as_read']
          remove << 'UNREAD'
        end

        post("me/messages/#{input['message_id']}/modify").
          payload(
            addLabelIds: add.presence,
            removeLabelIds: remove.presence
          )
      end,

      output_fields: lambda do |_object_defs, _connection, _config|
        [
          { name: 'id' },
          { name: 'labelIds', type: 'array', of: 'string' },
          { name: 'threadId' }
        ]
      end
    }

    # (Optional) You can add "send_message" later with scope gmail.send by creating a MIME and POST to users.messages.send
  },

  # ---------- Triggers ----------
  triggers: {
    new_message: {
      title: 'New message (polling)',
      subtitle: 'Poll for new mail using Gmail query/labels',
      description: lambda do |_input, _label|
        'Polls /users/me/messages with a time cursor using Gmail search `after:`. ' \
        'Tip: prefer an explicit query to reduce noise (e.g., `in:inbox -category:promotions`).'
      end,

      input_fields: lambda do |_object_defs, _connection, _config|
        [
          { name: 'q', hint: 'Optional Gmail query. Example: in:inbox -category:promotions', optional: true },
          { name: 'label_ids', label: 'Filter by labels', type: 'array', of: 'string', control_type: 'multiselect', pick_list: 'labels', optional: true },
          {
            name: 'since',
            label: 'Start from (ISO8601)',
            hint: 'Used only for the first poll; later runs continue from the last seen email time.',
            type: 'date_time',
            optional: true
          },
          { name: 'include_spam_trash', type: 'boolean', control_type: 'checkbox', label: 'Include Spam/Trash', optional: true },
          { name: 'page_size', type: 'integer', hint: '1–500 (default 100 from Gmail). Smaller sizes reduce per-poll work.', optional: true }
        ]
      end,

      poll: lambda do |_connection, input, closure|
        # closure is last_internal_ms (Gmail internalDate, ms since epoch). Convert to seconds for Gmail q=after: (see docs).
        # If no closure yet, use provided 'since' or now - 1 hour.
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
        q_parts << "after:#{after_seconds}" # Gmail interprets numeric after/before as epoch seconds
        q = q_parts.compact.join(' ').strip

        list = get('me/messages').
                 params(
                   q: q,
                   labelIds: input['label_ids'],
                   includeSpamTrash: input['include_spam_trash'],
                   maxResults: (input['page_size'] || 100)
                 )

        ids = Array(list['messages']).map { |m| m['id'] }
        events = []

        unless ids.blank?
          events = ids.map do |id|
            detail = get("me/messages/#{id}").params(format: 'full')
            call('normalize_message', detail)
          end

          # Advance cursor to the max internalDate seen
          max_ms = events.compact.map { |e| e['internal_date'] }.compact.map { |t| Time.parse(t).to_i * 1000 }.max
          closure = max_ms if max_ms
        end

        {
          events: events,
          next_poll: closure,
          can_poll_more: false # keep simple; Workato will repoll later
        }
      end,

      dedup: lambda do |record|
        # Combine message id with internalDate to dedupe
        "#{record['id']}@#{record['internal_date']}"
      end,

      output_fields: lambda do |object_definitions, _connection, _config|
        object_definitions['message']
      end,

      sample_output: lambda do
        {}
      end
    }
  }
}
