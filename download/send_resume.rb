# Build JSON body for API requiring Base64-in-JSON (no line breaks),
# plus integrity header. Return both an object payload and a raw JSON string.
# Inputs expected (configure in the Inputs section):
# - file_content (string): map your file's *content bytes* here
# - file_name    (string, optional)
# - mime_type    (string, optional)
# - extra_json   (string, optional): JSON object to merge into the payload

require 'base64'
require 'json'
require 'digest'

# --- Gather inputs ---
bytes_in = input['file_content']
raise 'file_content is required' if bytes_in.nil?

# Ensure binary string (avoid any implicit encoding surprises)
bytes = bytes_in.dup
bytes = bytes.force_encoding('BINARY') if bytes.respond_to?(:force_encoding)

file_name = (input['file_name'].to_s.strip.empty? ? 'resume.bin' : input['file_name'].to_s)
mime_type = (input['mime_type'].to_s.strip.empty? ? 'application/octet-stream' : input['mime_type'].to_s)

# --- Encode & checksum ---
b64    = Base64.strict_encode64(bytes)       # << no line breaks
sha256 = Digest::SHA256.hexdigest(bytes)

# --- Build payload { fileName, mimeType, data } ---
payload = {
  fileName: file_name,
  mimeType: mime_type,
  data:     b64
}

# Optionally merge additional JSON fields (e.g., {"candidateId":123, "candidateName":"Ada"})
if input['extra_json'].to_s.strip != ''
  begin
    extra = JSON.parse(input['extra_json'].to_s)
    raise 'extra_json must be a JSON object' unless extra.is_a?(Hash)
    # Merge (string keys are fine for JSON); prefer caller-provided keys as-is
    payload.merge!(extra)
  rescue => e
    # Return early with a helpful error but still include a valid payload
    return {
      error: "Invalid extra_json: #{e.message}",
      payload: payload,
      payload_json: JSON.generate(payload),
      headers: { 'Content-Type' => 'application/json', 'X-File-SHA256' => sha256 },
      sha256: sha256,
      file_name: file_name,
      mime_type: mime_type,
      byte_length: bytes.bytesize,
      base64_length: b64.length,
      roundtrip_ok: (Base64.strict_decode64(b64) == bytes) # Strict ensures newlines won't interrupt output
    }
  end
end

{
  payload: payload,                           # Object to map into an HTTP JSON body
  payload_json: JSON.generate(payload),       # Raw JSON string
  headers: {
    'Content-Type' => 'application/json',
    'X-File-SHA256' => sha256
  },
  sha256: sha256,
  file_name: file_name,
  mime_type: mime_type,
  byte_length: bytes.bytesize,
  base64_length: b64.length,
  roundtrip_ok: (Base64.strict_decode64(b64) == bytes),
  error: nil
}


# Template output schema
{
  "payload": {
    "fileName": "Ada_Lovelace.pdf",
    "mimeType": "application/pdf",
    "data": "BASE64_STRING",
    "candidateId": 12345,
    "candidateName": "Ada Lovelace"
  },
  "payload_json": "{\"fileName\":\"Ada_Lovelace.pdf\",\"mimeType\":\"application/pdf\",\"data\":\"BASE64_STRING\",\"candidateId\":12345,\"candidateName\":\"Ada Lovelace\"}",
  "headers": {
    "Content-Type": "application/json",
    "X-File-SHA256": "9fdeadbeef..."
  },
  "sha256": "9fdeadbeef...",
  "file_name": "Ada_Lovelace.pdf",
  "mime_type": "application/pdf",
  "byte_length": 123456,
  "base64_length": 164608,
  "roundtrip_ok": true,
  "error": null
}
