# Notes on File Validation

## 1. Encoding and transport fundamentals
- Base64
  - RFC 4648 defines base 64, base 32, base 16 encoding schemes [IETF RFC 4648](https://datatracker.ietf.org/doc/html/rfc4648)
  - Summary from [RFC Editor](https://www.rfc-editor.org/info/rfc4648)
  - Context:
    - Newlines corrupt payloads, padding and whitespace is important.
- Data URLs
  - RFC 2397 defines the 'data' url scheme [RFC 2397 at RFC Editor](https://www.rfc-editor.org/info/rfc2397)
  - Context:
    - When upstream systems pass `data:*;base64`, know the precise grammar to safely strip prefixes before decoding.
- File uploads `multipart/form-data`
  - RFC 7578 on returning values from forms [IETF RFC 7578](https://datatracker.ietf.org/doc/html/rfc7578)
  - Context:
    - Details (boundaries, filenames, content dispositions, charsets) matter when uploading/downloading files
- JSON as transport `application/json`
  - RFC 8259 is the standard for JSON [IETF RFC 8259](https://datatracker.ietf.org/doc/html/rfc8259)
- MIME / media types
  - The canonical registry of media types [IANA](https://www.iana.org/assignments/media-types)

---

## 2. File containers
- PDF
  - Adobe PDF 1.7 is [ISO 32000-1](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf)
  - [QPDF](https://qpdf.readthedocs.io/en/stable/cli.html)
- ZIP
  - Why are `DOCX`/`XLSX`/`PPTX` ZIPs?
  - ZIP spec is [APPNOTE.TXT](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)
- Office Open XML (OOXML) / OPC
  - DOCX/XLSX/PPTX are OOXML packages inside ZIP
  - Sources
    - [ECMA-376](https://ecma-international.org/publications-and-standards/standards/ecma-376)
    - [OOXML overview](https://www.ecma-international.org/wp-content/uploads/OfficeXML-White-Paper-v2008-10-03.pdf)
    - [Overview from LoC](https://www.loc.gov/preservation/digital/formats/fdd/fdd000363.shtml)
- OLE / CFB (legacy .doc/.xls/.ppt)
  - Microsoft MS-CFB [spec](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/53989ce4-7b05-4f8d-829b-d08d6148375b) covering magic header, byte order (OxFFFE), sector sizes, FAT/miniFAT, etc)
  - Overview from [LoC](https://www.loc.gov/preservation/digital/formats/fdd/fdd000380.shtml)

---

## 3. Ruby essentials for binary and i/o
- Base64 API
  - [Base64 module - Ruby 2.5.3](https://ruby-doc.org/stdlib-2.5.3/libdoc/base64/rdoc/Base64.html)
  - [Base64 module - Ruby 3.3](https://docs.ruby-lang.org/en/3.3/Base64.html)
- Hashes
  - [`Digest::SHA256`](https://docs.ruby-lang.org/en/master/Digest/SHA256.html) used for integrity header checks
- Binary parsing
  - From `stdlib` use, `String#unpack`, and `Array#pack`.
  - Source
    - [Ruby doc - String#unpack](https://www.rubydoc.info/stdlib/core/2.0.0/String%3Aunpack)
    - [Ruby doc - Array#pack](https://rubydoc.info/stdlib/core/1.9.3/Array%3Apack)
    - [Packed Data guide](https://docs.ruby-lang.org/en/3.2/packed_data_rdoc.html)
- HTTP client
  - `Net::HTTP`
  - `Net::HTTP::Post`
- ZIP handling
  - `rubyzip` gem [docs](https://rubydoc.info/github/rubyzip/rubyzip)
- MIME detection helpers
  - Infer content-type
  - Resources
    - Rails' [`marcel`](https://github.com/rails/marcel) gem (content-based)
    - DB-driven [`mimemagic`](https://www.rubydoc.info/gems/marcel/1.0.4) gem

---

## 4. Putting it together in the context of Workato

---

## 5. Tools for inspection and validation
- qpdf
  - CLI and [docs](https://qpdf.readthedocs.io/en/stable/cli.html) for structural checks, re-building PDFS
  - Flag `--check` (useful in pipelines)
- Hex editor
  - Various tools available
- Kaitai Struct
  - Useful to understand binary formats
  - Watch structures decode live
  - Reference
    - https://kaitai.io/
    - https://github.com/kaitai-io/kaitai_struct_formats

---

# References
- Base64, canonical form &rarr; [RFC 4648](https://datatracker.ietf.org/doc/html/rfc4648)
- Data URLs &rarr; [RFC 2397](https://www.rfc-editor.org/rfc/rfc2397.html)
- Multipart &rarr; [RFC 7578](https://datatracker.ietf.org/doc/html/rfc7578) (form file uploads)
- JSON &rarr; [RFC 8259](https://datatracker.ietf.org/doc/html/rfc8259) (`application/json`)
- MIME registry &rarr; [IANA Media Types ](https://www.iana.org/assignments/media-types)
- PDF &rarr; ISO 32000-1 / [Adobe PDF 1.7](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf); [qpdf docs](https://qpdf.readthedocs.io/en/stable/cli.html)
- OLE/CFB &rarr; [MS-CFB](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/53989ce4-7b05-4f8d-829b-d08d6148375b)
- OOXML / OPC &rarr; [ECMA-376](https://ecma-international.org/publications-and-standards/standards/ecma-376), [OPC overview](https://www.loc.gov/preservation/digital/formats/fdd/fdd000363.shtml)
- ZIP &rarr; [PKWARE APPNOTE.TXT](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)
- 
