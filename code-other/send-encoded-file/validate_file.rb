# Detect encoding (binary vs base64), infer file type (pdf/docx/doc/zip/etc),
# run lightweight integrity checks, and return BOTH normalized strict base64
# and (optionally) raw decoded bytes for resending.
#
# Inputs (configure these in the Ruby Snippet's Input section):
# - file_content      (String, REQUIRED): the content bytes OR a base64 string (may be data URI).
# - file_name         (String, optional): filename hint.
# - mime_type         (String, optional): MIME hint.
# - encoding_hint     (String, optional): 'auto' (default), 'binary', or 'base64'.
# - expected_sha256   (String, optional): if provided, compare against decoded bytes.
# - emit_raw_bytes    (String/Boolean, optional): 'true'|'false' (default 'false').
# - raw_bytes_max     (Integer, optional): max bytes to expose in 'decoded_bytes' (default 5_242_880).
#
# Outputs include:
# - content_encoding_detected, container_detected, file_kind, verdict, is_corrupt, reasons,
#   sha256, byte_length, base64_length, details, header_hex_sample, used_filename, used_mime_type,
#   normalized_base64, normalized_base64_length, normalized_data_uri, roundtrip_ok,
#   decoded_bytes_available, decoded_bytes_omitted_reason, decoded_bytes
# - error (Boolean), error_class (String), error_message (String), error_backtrace (Array<String>)

require 'base64'
require 'digest'

# ---------- Helpers ----------
def to_binary(str)
  s = str.dup
  s = s.force_encoding('BINARY') if s.respond_to?(:force_encoding)
  s
end

def hex_sample(bytes, n=32)
  bytes[0, n].to_s.each_byte.map { |b| "%02x" % b }.join
end

def file_struct_heuristics(bytes)
  return :pdf if bytes.start_with?("%PDF-")
  return :zip if bytes.start_with?("PK\x03\x04") || bytes.start_with?("PK\x05\x06") || bytes.start_with?("PK\x07\x08")
  return :ole if bytes.start_with?("\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b)
  return :text if bytes.valid_encoding? && bytes.ascii_only?
  :unknown
end

def likely_base64_string?(s)
  return false if s.nil? || s.empty?
  return false if s.include?("\x00") # likely binary if raw contains NUL
  return true  if s.start_with?('data:') && s.include?(';base64,') # data URI
  scrub = s.gsub(/\s+/, '')
  return false unless scrub.length % 4 == 0
  return false unless scrub.match?(/\A[A-Za-z0-9+\/]*={0,2}\z/)
  begin
    decoded = Base64.strict_decode64(scrub)
  rescue
    return false
  end
  return true if [:pdf, :zip, :ole].include?(file_struct_heuristics(decoded))
  non_printable = decoded.each_byte.count { |b| b < 9 || (b > 13 && b < 32) }
  (non_printable.to_f / [decoded.bytesize,1].max) > 0.05
end

def decode_if_base64(raw)
  if raw.start_with?('data:') && raw.include?(';base64,')
    b64 = raw.split(',', 2)[1].to_s
    begin
      return ['base64', Base64.strict_decode64(b64), b64.length, ['data URI base64']]
    rescue => e
      return ['base64', nil, b64.length, ["invalid base64 (data URI): #{e.message}"]]
    end
  end
  scrub = raw.gsub(/\s+/, '')
  begin
    decoded = Base64.strict_decode64(scrub)
    ['base64', decoded, scrub.length, []]
  rescue => e
    ['base64', nil, scrub.length, ["invalid base64: #{e.message}"]]
  end
end

def detect_container(bytes)
  case file_struct_heuristics(bytes)
  when :pdf then ['pdf', 'pdf']
  when :zip then ['zip', 'unknown']
  when :ole then ['ole', 'doc'] # legacy Office
  when :text then ['text', 'unknown']
  else ['unknown', 'unknown']
  end
end

# ---------- PDF checks ----------
def check_pdf(bytes)
  reasons = []
  ok = true
  details = {}

  header_ok = bytes.start_with?("%PDF-")
  details[:header_ok] = header_ok
  unless header_ok
    reasons << "Missing %PDF- header"
    return ['corrupt', reasons, details]
  end

  details[:version] = bytes[5, 3].to_s # e.g., "1.7"

  eof_pos = bytes.rindex("%%EOF")
  details[:has_eof] = !eof_pos.nil?
  details[:eof_pos] = eof_pos
  if eof_pos.nil? || eof_pos < bytes.bytesize - 2048
    ok = false
    reasons << "%%EOF not found near end"
  end

  sx_pos = bytes.rindex("startxref")
  details[:has_startxref] = !sx_pos.nil?
  if sx_pos
    tail = bytes[sx_pos + "startxref".length, 64].to_s
    if (m = tail.match(/(\d{1,20})/))
      xref_off = m[1].to_i
      details[:xref_offset] = xref_off
      if xref_off >= 0 && xref_off < bytes.bytesize
        slice = bytes[xref_off, 16_384].to_s
        xref_ok = slice.start_with?("xref") || slice.match?(/\A\d+\s+\d+\s+obj/)
        details[:xref_target_ok] = xref_ok
        unless xref_ok
          ok = false
          reasons << "startxref does not point to xref/object"
        end
      else
        ok = false
        reasons << "startxref offset out of range"
      end
    else
      ok = false
      reasons << "startxref offset not parsable"
    end
  else
    ok = false
    reasons << "Missing startxref"
  end

  has_obj = bytes.include?(" obj") && bytes.include?("endobj")
  details[:has_object_pairs] = has_obj
  ok = false unless has_obj
  reasons << "No object markers found" unless has_obj

  [ok ? 'ok' : 'corrupt', reasons, details]
end

# ---------- ZIP / OOXML checks ----------
def find_eocd(bytes)
  max_scan = [bytes.bytesize, 70_000].min
  window = bytes[-max_scan, max_scan]
  sig = "PK\x05\x06"
  rel = window.rindex(sig)
  return nil unless rel
  (bytes.bytesize - max_scan) + rel
end

def le16(s); s.unpack1('v'); end
def le32(s); s.unpack1('V'); end

def list_zip_entries(bytes, cd_offset, cd_size)
  names = []
  pos = cd_offset
  cd_end = cd_offset + cd_size
  while pos < cd_end
    return [names, "central directory overflow"] if pos + 46 > bytes.bytesize
    sig = bytes[pos, 4]
    return [names, "central directory signature mismatch"] unless sig == "PK\x01\x02"
    fname_len = le16(bytes[pos + 28, 2])
    extra_len = le16(bytes[pos + 30, 2])
    comment_len = le16(bytes[pos + 32, 2])
    name_off = pos + 46
    return [names, "name field overflow"] if name_off + fname_len > bytes.bytesize
    names << bytes[name_off, fname_len]
    pos = name_off + fname_len + extra_len + comment_len
  end
  [names, nil]
end

def check_zip(bytes)
  reasons = []
  details = {}
  ok = true

  eocd_off = find_eocd(bytes)
  return ['corrupt', ['EOCD not found (not a valid ZIP)'], { eocd_found: false }, 'zip-other'] if eocd_off.nil?
  details[:eocd_found] = true
  details[:eocd_offset] = eocd_off

  eocd = bytes[eocd_off, 22]
  cd_size   = le32(eocd[12, 4])
  cd_offset = le32(eocd[16, 4])
  details[:cd_size]   = cd_size
  details[:cd_offset] = cd_offset

  if cd_offset + cd_size > bytes.bytesize
    ok = false
    reasons << "Central directory out of range"
  end

  names, err = list_zip_entries(bytes, cd_offset, cd_size)
  if err
    ok = false
    reasons << err
  end

  details[:entries_count]  = names.length
  details[:entries_sample] = names.take(10)

  kind = 'zip-other'
  if names.include?('[Content_Types].xml')
    if names.any? { |n| n.start_with?('word/') }
      kind = 'docx'
      core = names.include?('word/document.xml')
      details[:ooxml_core_present] = core
      ok &&= core
      reasons << "Missing word/document.xml" unless core
    elsif names.any? { |n| n.start_with?('xl/') }
      kind = 'xlsx'
      core = names.include?('xl/workbook.xml')
      details[:ooxml_core_present] = core
      ok &&= core
      reasons << "Missing xl/workbook.xml" unless core
    elsif names.any? { |n| n.start_with?('ppt/') }
      kind = 'pptx'
      core = names.include?('ppt/presentation.xml')
      details[:ooxml_core_present] = core
      ok &&= core
      reasons << "Missing ppt/presentation.xml" unless core
    end
  end

  [ok ? 'ok' : 'corrupt', reasons, details, kind]
end

# ---------- OLE/CFB checks ----------
def check_ole(bytes)
  reasons = []
  details = {}
  ok = true

  sig_ok = bytes.start_with?("\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b)
  details[:header_signature_ok] = sig_ok
  return ['corrupt', ['Missing OLE/CFB header signature'], details, 'unknown'] unless sig_ok

  byte_order = bytes[28, 2]
  details[:byte_order] = byte_order ? byte_order.unpack1('v') : nil
  unless byte_order && byte_order == "\xFE\xFF".b
    ok = false
    reasons << "Unexpected byte order (expected 0xFFFE)"
  end

  sector_shift = bytes[30, 2]&.unpack1('v')
  details[:sector_shift] = sector_shift
  unless [9, 12].include?(sector_shift)
    ok = false
    reasons << "Invalid sector shift (expected 9 or 12)"
  end

  ok &&= bytes.bytesize >= 1536
  reasons << "File too small for OLE container" if bytes.bytesize < 1536

  [ok ? 'suspect' : 'corrupt', reasons, details, 'doc']
end

# ---------- MAIN ----------
begin
  # 1) Inputs
  raw_in    = input['file_content'] or raise('file_content is required')
  file_name = (input['file_name'].to_s.strip.empty? ? nil : input['file_name'].to_s)
  mime_hint = (input['mime_type'].to_s.strip.empty? ? nil : input['mime_type'].to_s)
  enc_hint  = (input['encoding_hint'].to_s.strip.empty? ? 'auto' : input['encoding_hint'].to_s.downcase)
  expected  = (input['expected_sha256'].to_s.strip.empty? ? nil : input['expected_sha256'].to_s.downcase)

  emit_raw  = input['emit_raw_bytes'].to_s.strip.downcase
  emit_raw  = %w[true 1 yes y].include?(emit_raw) # default false
  raw_max   = input['raw_bytes_max'].to_i
  raw_max   = 5_242_880 if raw_max <= 0 # ~5 MB default

  # 2) Determine encoding & decode
  content_encoding_detected = nil
  decoded    = nil
  base64_len = nil
  enc_notes  = []

  raw_bin = to_binary(raw_in)

  if enc_hint == 'binary'
    content_encoding_detected = 'binary'
    decoded = raw_bin
  elsif enc_hint == 'base64'
    content_encoding_detected = 'base64'
    begin
      scrub = raw_in.start_with?('data:') && raw_in.include?(';base64,') ? raw_in.split(',', 2)[1].to_s : raw_in.gsub(/\s+/, '')
      decoded = Base64.strict_decode64(scrub)
      base64_len = scrub.length
    rescue => e
      return {
        error: true,
        error_class: e.class.name,
        error_message: "invalid base64: #{e.message}",
        error_backtrace: caller,
        content_encoding_detected: 'base64',
        container_detected: 'unknown',
        file_kind: 'unknown',
        verdict: 'corrupt',
        is_corrupt: true,
        reasons: ["invalid base64: #{e.message}"],
        sha256: nil,
        byte_length: 0,
        base64_length: scrub.length,
        details: { error: 'base64 decode failed' },
        header_hex_sample: nil,
        used_filename: file_name,
        used_mime_type: mime_hint,
        normalized_base64: nil,
        normalized_base64_length: 0,
        normalized_data_uri: nil,
        roundtrip_ok: false,
        decoded_bytes_available: false,
        decoded_bytes_omitted_reason: "base64 decode failed",
        decoded_bytes: nil
      }
    end
  else
    if likely_base64_string?(raw_in)
      enc, dec, b64len, notes = decode_if_base64(raw_in)
      content_encoding_detected = enc
      decoded = dec
      base64_len = b64len
      enc_notes.concat(notes)
      if decoded.nil?
        return {
          error: true,
          error_class: 'Base64DecodeError',
          error_message: notes.join('; '),
          error_backtrace: caller,
          content_encoding_detected: 'base64',
          container_detected: 'unknown',
          file_kind: 'unknown',
          verdict: 'corrupt',
          is_corrupt: true,
          reasons: notes,
          sha256: nil,
          byte_length: 0,
          base64_length: base64_len,
          details: { error: 'base64 decode failed' },
          header_hex_sample: nil,
          used_filename: file_name,
          used_mime_type: mime_hint,
          normalized_base64: nil,
          normalized_base64_length: 0,
          normalized_data_uri: nil,
          roundtrip_ok: false,
          decoded_bytes_available: false,
          decoded_bytes_omitted_reason: "base64 decode failed",
          decoded_bytes: nil
        }
      end
    else
      content_encoding_detected = 'binary'
      decoded = raw_bin
    end
  end

  decoded = to_binary(decoded)
  sha = Digest::SHA256.hexdigest(decoded)
  reasons = enc_notes.dup
  reasons << "SHA-256 mismatch (expected #{expected}, got #{sha})" if expected && expected != sha

  # 3) Detect container & run checks
  container, kind = detect_container(decoded)
  verdict = 'ok'
  details = {}

  case container
  when 'pdf'
    v, v_reasons, pdf_details = check_pdf(decoded)
    verdict = v
    reasons.concat(v_reasons)
    details.merge!(pdf_details)
  when 'zip'
    v, v_reasons, zip_details, refined = check_zip(decoded)
    verdict = v
    reasons.concat(v_reasons)
    details.merge!(zip_details)
    kind = refined
  when 'ole'
    v, v_reasons, ole_details, refined = check_ole(decoded)
    verdict = v
    reasons.concat(v_reasons)
    details.merge!(ole_details)
    kind = refined
  when 'text'
    verdict = expected ? (reasons.any? { |r| r.start_with?('SHA-256 mismatch') } ? 'suspect' : 'ok') : 'ok'
  else
    verdict = expected ? (reasons.any? { |r| r.start_with?('SHA-256 mismatch') } ? 'suspect' : 'ok') : 'suspect'
    reasons << "Unrecognized file signature"
  end
  is_corrupt = (verdict == 'corrupt')

  # 4) Define vars referenced in output
  normalized_base64 = Base64.strict_encode64(decoded)
  normalized_base64_length = normalized_base64.length
  normalized_data_uri = "data:#{(mime_hint || 'application/octet-stream')};base64,#{normalized_base64}"
  roundtrip_ok = (Base64.strict_decode64(normalized_base64) == decoded)

  decoded_bytes_available = false
  decoded_bytes_omitted_reason = nil
  decoded_bytes_out = nil
  if emit_raw
    if decoded.bytesize <= raw_max
      decoded_bytes_out = decoded
      decoded_bytes_available = true
    else
      decoded_bytes_omitted_reason = "decoded bytes (#{decoded.bytesize}) exceed raw_bytes_max (#{raw_max}); use normalized_base64"
    end
  else
    decoded_bytes_omitted_reason = "emit_raw_bytes=false; enable to expose raw bytes"
  end

  # 5) Build & return output
  output = {
    content_encoding_detected: content_encoding_detected,
    container_detected: container,
    file_kind: kind,
    verdict: verdict,
    is_corrupt: is_corrupt,
    reasons: reasons,
    sha256: sha,
    byte_length: decoded.bytesize,
    base64_length: base64_len,
    details: details,
    header_hex_sample: hex_sample(decoded, 32),
    used_filename: file_name,
    used_mime_type: mime_hint,

    normalized_base64: normalized_base64,
    normalized_base64_length: normalized_base64_length,
    normalized_data_uri: normalized_data_uri,
    roundtrip_ok: roundtrip_ok,

    decoded_bytes_available: decoded_bytes_available,
    decoded_bytes_omitted_reason: decoded_bytes_omitted_reason,
    decoded_bytes: decoded_bytes_out,

    error: false,
    error_class: nil,
    error_message: nil,
    error_backtrace: nil
  }

rescue => e
  # Global safety: include a stack trace on any unexpected error
   output = {
    error: true,
    error_class: e.class.name,
    error_message: e.message,
    error_backtrace: e.backtrace,

    # Minimal context to aid debugging
    used_filename: (defined?(file_name) ? file_name : nil),
    used_mime_type: (defined?(mime_hint) ? mime_hint : nil),
    content_encoding_detected: (defined?(content_encoding_detected) ? content_encoding_detected : nil),
    byte_length: (defined?(decoded) && decoded ? decoded.bytesize : 0),
    header_hex_sample: (defined?(decoded) && decoded ? hex_sample(decoded, 32) : nil),

    # Keep the rest present but nil
    container_detected: nil,
    file_kind: nil,
    verdict: 'corrupt',
    is_corrupt: true,
    reasons: ["Unhandled exception"],
    sha256: nil,
    base64_length: (defined?(base64_len) ? base64_len : nil),
    details: {},
    normalized_base64: nil,
    normalized_base64_length: 0,
    normalized_data_uri: nil,
    roundtrip_ok: false,
    decoded_bytes_available: false,
    decoded_bytes_omitted_reason: "exception",
    decoded_bytes: nil
  }
end
