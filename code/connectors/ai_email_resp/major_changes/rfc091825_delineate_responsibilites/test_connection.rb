actions: {

  test_connection: {
    title: 'Test connection and permissions',
    subtitle: 'Verify API access and permissions',
    description: 'Tests connectivity to Vertex AI and Google Drive APIs, validates permissions, and returns diagnostic information',
    
    help: {
      body: 'Use this action to verify your connection is working and has the required permissions. ' \
            'Useful for debugging and monitoring connection health.',
      learn_more_url: 'https://cloud.google.com/vertex-ai/docs/reference/rest',
      learn_more_text: 'API Documentation'
    },
    
    input_fields: lambda do |object_definitions|
      [
        {
          name: 'test_vertex_ai',
          label: 'Test Vertex AI',
          type: 'boolean',
          control_type: 'checkbox',
          default: true,
          optional: true,
          hint: 'Test Vertex AI API access and permissions'
        },
        {
          name: 'test_drive',
          label: 'Test Google Drive',
          type: 'boolean',
          control_type: 'checkbox',
          default: true,
          optional: true,
          hint: 'Test Google Drive API access (requires Drive scope)'
        },
        {
          name: 'test_models',
          label: 'Test model access',
          type: 'boolean',
          control_type: 'checkbox',
          default: false,
          optional: true,
          hint: 'Validate access to specific AI models (slower)'
        },
        {
          name: 'test_index',
          label: 'Test Vector Search index',
          type: 'boolean',
          control_type: 'checkbox',
          default: false,
          optional: true,
          hint: 'Validate Vector Search index access'
        },
        {
          name: 'index_id',
          label: 'Index ID',
          type: 'string',
          optional: true,
          ngIf: 'input.test_index == true',
          hint: 'Vector Search index to test (projects/PROJECT/locations/REGION/indexes/INDEX_ID)'
        },
        {
          name: 'verbose',
          label: 'Verbose output',
          type: 'boolean',
          control_type: 'checkbox',
          default: false,
          optional: true,
          hint: 'Include detailed diagnostic information'
        }
      ]
    end,
    
    execute: lambda do |connection, input|
      results = {
        'timestamp' => Time.now.iso8601,
        'environment' => {
          'project' => connection['project'],
          'region' => connection['region'],
          'api_version' => connection['version'] || 'v1',
          'auth_type' => connection['auth_type'],
          'host' => connection['developer_api_host']
        },
        'tests_performed' => [],
        'errors' => [],
        'warnings' => [],
        'all_tests_passed' => true
      }
      
      # Test Vertex AI Connection
      if input['test_vertex_ai'] != false
        begin
          start_time = Time.now
          
          # Test basic connectivity
          datasets_response = get("projects/#{connection['project']}/locations/#{connection['region']}/datasets").
            params(pageSize: 1).
            after_error_response(/.*/) do |code, body, _header, message|
              raise "Vertex AI API error (#{code}): #{message}"
            end
          
          vertex_test = {
            'service' => 'Vertex AI',
            'status' => 'connected',
            'response_time_ms' => ((Time.now - start_time) * 1000).round,
            'permissions_validated' => []
          }
          
          # Check specific permissions based on response
          if datasets_response
            vertex_test['permissions_validated'] << 'aiplatform.datasets.list'
          end
          
          # Test model access if requested
          if input['test_models']
            begin
              models_response = get("projects/#{connection['project']}/locations/#{connection['region']}/models").
                params(pageSize: 1)
              vertex_test['permissions_validated'] << 'aiplatform.models.list'
              vertex_test['models_accessible'] = true
            rescue => e
              vertex_test['models_accessible'] = false
              results['warnings'] << "Cannot list models: #{e.message}"
            end
            
            # Test specific model access
            begin
              model_test = get("https://#{connection['region']}-aiplatform.googleapis.com/v1/publishers/google/models/gemini-1.5-pro")
              vertex_test['gemini_access'] = true
              vertex_test['permissions_validated'] << 'aiplatform.models.predict'
            rescue => e
              vertex_test['gemini_access'] = false
              results['warnings'] << "Cannot access Gemini models: #{e.message}"
            end
          end
          
          results['tests_performed'] << vertex_test
          
        rescue => e
          results['tests_performed'] << {
            'service' => 'Vertex AI',
            'status' => 'failed',
            'error' => e.message
          }
          results['errors'] << "Vertex AI: #{e.message}"
          results['all_tests_passed'] = false
        end
      end
      
      # Test Google Drive Connection
      if input['test_drive'] != false
        begin
          start_time = Time.now
          
          drive_response = get('https://www.googleapis.com/drive/v3/files').
            params(pageSize: 1, q: "trashed = false", fields: 'files(id,name,mimeType)').
            after_error_response(/.*/) do |code, body, _header, message|
              if code == 403
                raise "Drive API not enabled or missing scope"
              elsif code == 401
                raise "Authentication failed - check OAuth token"
              else
                raise "Drive API error (#{code}): #{message}"
              end
            end
          
          drive_test = {
            'service' => 'Google Drive',
            'status' => 'connected',
            'response_time_ms' => ((Time.now - start_time) * 1000).round,
            'files_found' => drive_response['files'].length,
            'permissions_validated' => ['drive.files.list']
          }
          
          # If verbose, include sample file info
          if input['verbose'] && drive_response['files'].any?
            drive_test['sample_file'] = drive_response['files'].first
          end
          
          # Test file read permission
          if drive_response['files'].any?
            file_id = drive_response['files'].first['id']
            begin
              get("https://www.googleapis.com/drive/v3/files/#{file_id}").
                params(fields: 'id,size')
              drive_test['permissions_validated'] << 'drive.files.get'
              drive_test['can_read_files'] = true
            rescue => e
              drive_test['can_read_files'] = false
              results['warnings'] << "Cannot read file content: #{e.message}"
            end
          end
          
          results['tests_performed'] << drive_test
          
        rescue => e
          results['tests_performed'] << {
            'service' => 'Google Drive',
            'status' => 'failed',
            'error' => e.message
          }
          results['errors'] << "Google Drive: #{e.message}"
          results['all_tests_passed'] = false
        end
      end
      
      # Test Vector Search Index
      if input['test_index'] && input['index_id'].present?
        begin
          start_time = Time.now
          index_id = input['index_id']
          
          # Validate index format
          unless index_id.match?(/^projects\/[^\/]+\/locations\/[^\/]+\/indexes\/[^\/]+$/)
            raise "Invalid index ID format. Expected: projects/PROJECT/locations/REGION/indexes/INDEX_ID"
          end
          
          # Get index details
          index_response = get(index_id).
            after_error_response(/.*/) do |code, body, _header, message|
              if code == 404
                raise "Index not found"
              elsif code == 403
                raise "Missing permission: aiplatform.indexes.get"
              else
                raise "Index API error (#{code}): #{message}"
              end
            end
          
          index_test = {
            'service' => 'Vector Search Index',
            'status' => 'connected',
            'response_time_ms' => ((Time.now - start_time) * 1000).round,
            'index_details' => {
              'display_name' => index_response['displayName'],
              'state' => index_response['state'],
              'index_update_method' => index_response['indexUpdateMethod']
            }
          }
          
          # Check deployment status
          deployed_indexes = index_response['deployedIndexes'] || []
          if deployed_indexes.empty?
            index_test['deployed'] = false
            results['warnings'] << "Index exists but is not deployed"
          else
            index_test['deployed'] = true
            index_test['deployed_count'] = deployed_indexes.length
          end
          
          # Check index stats if available
          if index_response['indexStats']
            index_test['stats'] = {
              'vectors_count' => index_response['indexStats']['vectorsCount'],
              'shards_count' => index_response['indexStats']['shardsCount']
            }
          end
          
          results['tests_performed'] << index_test
          
        rescue => e
          results['tests_performed'] << {
            'service' => 'Vector Search Index',
            'status' => 'failed',
            'error' => e.message
          }
          results['errors'] << "Vector Search: #{e.message}"
          results['all_tests_passed'] = false
        end
      end
      
      # API Quotas Check (optional)
      if input['verbose']
        begin
          # Check Vertex AI quotas
          quotas = {
            'api_calls_per_minute' => {
              'gemini_pro' => 300,
              'gemini_flash' => 600,
              'embeddings' => 600
            },
            'notes' => 'These are default quotas. Actual quotas may vary by project.'
          }
          results['quota_info'] = quotas
        rescue => e
          results['warnings'] << "Could not retrieve quota information: #{e.message}"
        end
      end
      
      # Summary and recommendations
      results['summary'] = {
        'total_tests' => results['tests_performed'].length,
        'passed' => results['tests_performed'].count { |t| t['status'] == 'connected' },
        'failed' => results['tests_performed'].count { |t| t['status'] == 'failed' }
      }
      
      # Add recommendations if there are issues
      if results['errors'].any? || results['warnings'].any?
        results['recommendations'] = []
        
        if results['errors'].any? { |e| e.include?('Drive API not enabled') }
          results['recommendations'] << 'Enable Google Drive API in Cloud Console'
        end
        
        if results['errors'].any? { |e| e.include?('missing scope') }
          results['recommendations'] << 'Re-authenticate with Drive scope: https://www.googleapis.com/auth/drive.readonly'
        end
        
        if results['warnings'].any? { |w| w.include?('not deployed') }
          results['recommendations'] << 'Deploy your Vector Search index to an endpoint'
        end
      end
      
      # Set final status
      results['overall_status'] = if results['all_tests_passed']
        'healthy'
      elsif results['errors'].empty?
        'degraded'
      else
        'unhealthy'
      end
      
      results
    end,
    
    output_fields: lambda do |object_definitions|
      [
        { name: 'timestamp', type: 'datetime' },
        { name: 'overall_status', type: 'string' },
        { name: 'all_tests_passed', type: 'boolean' },
        { name: 'environment', type: 'object', properties: [
          { name: 'project', type: 'string' },
          { name: 'region', type: 'string' },
          { name: 'api_version', type: 'string' },
          { name: 'auth_type', type: 'string' },
          { name: 'host', type: 'string' }
        ]},
        { name: 'tests_performed', type: 'array', of: 'object' },
        { name: 'errors', type: 'array', of: 'string' },
        { name: 'warnings', type: 'array', of: 'string' },
        { name: 'summary', type: 'object', properties: [
          { name: 'total_tests', type: 'integer' },
          { name: 'passed', type: 'integer' },
          { name: 'failed', type: 'integer' }
        ]},
        { name: 'recommendations', type: 'array', of: 'string' },
        { name: 'quota_info', type: 'object' }
      ]
    end,
    
    sample_output: lambda do |_connection, _input|
      {
        'timestamp' => '2024-01-15T10:30:00Z',
        'overall_status' => 'healthy',
        'all_tests_passed' => true,
        'environment' => {
          'project' => 'my-project',
          'region' => 'us-central1',
          'api_version' => 'v1',
          'auth_type' => 'custom',
          'host' => 'app.eu'
        },
        'tests_performed' => [
          {
            'service' => 'Vertex AI',
            'status' => 'connected',
            'response_time_ms' => 245,
            'permissions_validated' => ['aiplatform.datasets.list']
          }
        ],
        'errors' => [],
        'warnings' => [],
        'summary' => {
          'total_tests' => 1,
          'passed' => 1,
          'failed' => 0
        }
      }
    end
  }
}
