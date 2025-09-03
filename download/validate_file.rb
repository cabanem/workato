# Detect encoding (binary vs base64), infer file type (pdf/docx/doc/zip/etc),
# and run lightweight integrity checks. Returns a verdict and diagnostics.
#
# Inputs (configure these in the Ruby Snippet's Input section):
# - file_content (String)        : REQUIRED. The content bytes or a base64 string.
# - file_name    (String, opt)   : Optional filename; used for hints only.
# - mime_type    (String, opt)   : Optional MIME hint; not required.
# - encoding_hint(String, opt)   : 'auto' (default), 'binary', or 'base64'
# - expected_sha256 (String, opt): Optional SHA-256 to compare against decoded bytes.
#
# Outputs (declare via Output schema; see example JSON after this block):
# - content_encoding_detected   : 'binary' or 'base64'
# - container_detected          : 'pdf'|'zip'|'ole'|'text'|'unknown'
# - file_kind                   : 'pdf'|'docx'|'xlsx'|'pptx'|'doc'|'zip-other'|'unknown'
# - verdict                     : 'ok'|'suspect'|'corrupt'
# - is_corrupt                  : true/false  (true if verdict == 'corrupt')
# - reasons                     : [String]    (why the verdict)
# - sha256                      : hex digest of decoded bytes
# - byte_length                 : Integer     (decoded length)
# - base64_length               : Integer or nil (if input looked like base64)
# - details                     : Hash        (type-specific checks)
# - header_hex_sample           : String      (first 32 bytes hex, for logs)
# - used_filename               : String or nil
# - used_mime_type              : String or nil

require 'base64'
require 'digest'

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
  return :text if bytes.valid_encoding? && bytes.encoding.name == "UTF-8" && bytes.ascii_only?
  :unknown
end

def likely_base64_string?(s)
  # Early out
  return false if s.nil? || s.empty?
  return false if s.include?("\x00") # likely binary if raw contains NUL **smells like
  return true  if s.start_with?('data:') && s.include?(';base64,') # Strip data URI prefix if present
  scrub = s.gsub(/\s+/, '')
  return false unless scrub.length % 4 == 0
  return false unless scrub.match?(/\A[A-Za-z0-9+\/]*={0,2}\z/)
  # Try decoding -- safely
  begin
    decoded = Base64.strict_decode64(scrub)
  rescue
    return false
  end
  # Heuristic: decoded should look like known stuct or have enough non-text bytes
  return true if [:pdf, :zip, :ole].include?(file_struct_heuristics(decoded))
  non_printable = decoded.each_byte.count { |b| b < 9 || (b > 13 && b < 32) }
  (non_printable.to_f / [decoded.bytesize,1].max) > 0.05
end

def decode_if_base64(raw)
  notes = []
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
    return ['base64', decoded, scrub.length, []]
  rescue => e
    return ['base64', nil, scrub.length, ["invalid base64: #{e.message}"]]
  end
end

def detect_container(bytes)
  case file_struct_heuristics(bytes)
  when :pdf then ['pdf', 'pdf']
  when :zip then ['zip', 'unknown']
  when :ole then ['ole', 'doc'] # OLE CFB common for .doc/.xls/.ppt; we default to 'doc'
  when :text then ['text', 'unknown']
  else ['unknown', 'unknown']
  end
end

# ---- PDF integrity checks ---------------------------------------------------
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

  # EOF marker near end
  eof_pos = bytes.rindex("%%EOF")
  details[:has_eof] = !eof_pos.nil?
  details[:eof_pos] = eof_pos
  if eof_pos.nil? || eof_pos < bytes.bytesize - 2048
    ok = false
    reasons << "%%EOF not found near end"
  end

  # startxref should exist and point to something reasonable
  sx_pos = bytes.rindex("startxref")
  details[:has_startxref] = !sx_pos.nil?
  if sx_pos
    # grab next number after startxref
    tail = bytes[sx_pos + "startxref".length, 64].to_s
    if (m = tail.match(/(\d{1,20})/))
      xref_off = m[1].to_i
      details[:xref_offset] = xref_off
      if xref_off >= 0 && xref_off < bytes.bytesize
        slice = bytes[xref_off, 16_384].to_s
        # Valid if 'xref' table OR object header for xref stream
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

  # must contain at least one object pair
  has_obj = bytes.include?(" obj") && bytes.include?("endobj")
  details[:has_object_pairs] = has_obj
  unless has_obj
    ok = false
    reasons << "No object markers found"
  end

  verdict = ok ? 'ok' : 'corrupt'
  [verdict, reasons, details]
end

# ---- ZIP / OOXML integrity checks ----
# docx/xlsx/pptx
def find_eocd(bytes)
  # EOCD signature 'PK\x05\x06' can be up to 65,535 + 22 bytes from EOF
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
    # lengths
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

  # Parse EOCD
  # struct:
  #  0 signature (4) = 0x06054b50
  #  4 disk_num (2)
  #  6 cd_start_disk (2)
  #  8 cd_records_disk (2)
  # 10 cd_records_total (2)
  # 12 cd_size (4)
  # 16 cd_offset (4)
  # 20 comment_len (2)
  eocd = bytes[eocd_off, 22]
  cd_size   = le32(eocd[12, 4])
  cd_offset = le32(eocd[16, 4])
  details[:cd_size] = cd_size
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

  # Classify OOXML types
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

# ---- OLE/CFB checks ----
# legacy .doc/.xls/.ppt
def check_ole(bytes)
  reasons = []
  details = {}
  ok = true

  sig_ok = bytes.start_with?("\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b)
  details[:header_signature_ok] = sig_ok
  return ['corrupt', ['Missing OLE/CFB header signature'], details, 'unknown'] unless sig_ok

  # Byte order should be 0xFFFE @ offset 28..29
  byte_order = bytes[28, 2]
  details[:byte_order] = byte_order ? byte_order.unpack1('v') : nil
  unless byte_order && byte_order == "\xFE\xFF".b
    ok = false
    reasons << "Unexpected byte order (expected 0xFFFE)"
  end

  # Sector shift @ 30..31: 0x0009 (512) or 0x000C (4096)
  sector_shift = bytes[30, 2]&.unpack1('v')
  details[:sector_shift] = sector_shift
  unless [9, 12].include?(sector_shift)
    ok = false
    reasons << "Invalid sector shift (expected 9 or 12)"
  end

  # Heuristic size sanity
  ok &&= bytes.bytesize >= 1536 # small guard
  reasons << "File too small for OLE container" if bytes.bytesize < 1536

  # Cannot completely parse streams w/o extra code; mark 'suspect'
  verdict = ok ? 'suspect' : 'corrupt'
  [verdict, reasons, details, 'doc']
end

# ---- MAIN -------------------------------------------------------------------
# 1) Gather inputs
raw_in    = input['file_content'] or raise('file_content is required')
file_name = (input['file_name'].to_s.strip.empty? ? nil : input['file_name'].to_s)
mime_hint = (input['mime_type'].to_s.strip.empty? ? nil : input['mime_type'].to_s)
enc_hint  = (input['encoding_hint'].to_s.strip.empty? ? 'auto' : input['encoding_hint'].to_s.downcase)
expected  = (input['expected_sha256'].to_s.strip.empty? ? nil : input['expected_sha256'].to_s.downcase)

emit_raw  = input['emit_raw_bytes'].to_s.strip.downcase
emit_raw  = %w[true 1 yes y].include?(emit_raw) # default false
raw_max   = input['raw_bytes_max'].to_i
raw_max   = 5_242_880 if raw_max <= 0 # ~5 MB default

# 2) Determine encoding, decode prn
content_encoding_detected = nil
decoded = nil
base64_len = nil
enc_notes = []

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

# Optional checksum verification
if expected && expected != sha
  reasons << "SHA-256 mismatch (expected #{expected}, got #{sha})"
end

# 3) Detect container and kind
container, kind = detect_container(decoded)

# If ZIP, refine kind and check
verdict = 'ok'
details = {}
case container
when 'pdf'
  verdict, v_reasons, pdf_details = check_pdf(decoded)
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
  # Text has no strong corruption notion; mark ok unless checksum mismatch
  verdict = expected ? (reasons.any? { |r| r.start_with?('SHA-256 mismatch') } ? 'suspect' : 'ok') : 'ok'
else
  # Unknown container; if checksum mismatch was set, mark suspect; else unknown-ok
  verdict = expected ? (reasons.any? { |r| r.start_with?('SHA-256 mismatch') } ? 'suspect' : 'ok') : 'suspect'
  reasons << "Unrecognized file signature"
end

is_corrupt = (verdict == 'corrupt')

# 4) Build output
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

  # Resend-ready encodings
  normalized_base64: normalized_base64,
  normalized_base64_length: normalized_base64_length,
  normalized_data_uri: normalized_data_uri,
  roundtrip_ok: roundtrip_ok,

  # Raw bytes (optional)
  decoded_bytes_available: decoded_bytes_available,
  decoded_bytes_omitted_reason: decoded_bytes_omitted_reason,
  decoded_bytes: decoded_bytes_out
}

# ========== Output Schema ==========
{
  "content_encoding_detected": "base64",
  "container_detected": "pdf",
  "file_kind": "pdf",
  "verdict": "ok",
  "is_corrupt": false,
  "reasons": ["data URI base64"],
  "sha256": "9fd3b7...c1",
  "byte_length": 123456,
  "base64_length": 164608,
  "details": {
    "version": "1.7",
    "has_eof": true,
    "eof_pos": 122345,
    "has_startxref": true,
    "xref_offset": 120000,
    "xref_target_ok": true,
    "entries_count": 0
  },
  "header_hex_sample": "255044462d312e37...",
  "used_filename": "resume.pdf",
  "used_mime_type": "application/pdf",
  "normalized_base64": "JVBERi0xLjcKJY... (strict, no newlines) ...",
  "normalized_base64_length": 164608,
  "normalized_data_uri": "data:application/pdf;base64,JVBERi0xLjcKJY...",
  "roundtrip_ok": true,
  "decoded_bytes_available": true,
  "decoded_bytes_omitted_reason": null,
  "decoded_bytes": "BINARY_WILL_BE_HERE_IF_ENABLED_AND_SMALL_ENOUGH"
}
