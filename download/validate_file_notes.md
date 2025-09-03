# Notes on File Validation

## 1. Encoding and transport fundamentals

## 2. File containers

## 3. Ruby essentials for binary and i/o
- Base64 API
  - https://ruby-doc.org/stdlib-2.5.3/libdoc/base64/rdoc/Base64.html
  - https://docs.ruby-lang.org/en/3.3/Base64.html
- Hashes
- Binary parsing
- HTTP client
- ZIP handling
  - `rubyzip` gem [docs](https://rubydoc.info/github/rubyzip/rubyzip)
- MIME detection helpers
  - Infer content-type
  - Resources
    - Rails' [`marcel`](https://github.com/rails/marcel) gem (content-based)
    - DB-driven [`mimemagic`](https://www.rubydoc.info/gems/marcel/1.0.4) gem

## 4. Putting it together in the context of Workato

## 5. Tools for inspection and validation
- qpdf
  - CLI and [docs](https://qpdf.readthedocs.io/en/stable/cli.html) for structural checks, re-building PDFS
  - Flag `--check` (useful in pipelines)
- Hex editor
  - Various tools available
- Kaitai Struct
  - Useful to understand binary formats
  - Watch structures decode live
  - https://kaitai.io/
  - https://github.com/kaitai-io/kaitai_struct_formats
 
## 6. References
- Base64, cononical form &rarr; RFC 4648
- Data URLs &rarr; RFC 2397
- Multipart &rarr; RFC 7578 (form file uploads)
- JSON &rarr; [RFC 8259](https://datatracker.ietf.org/doc/html/rfc8259) (`application/json`)
- MIME registry &rarr; [IANA Media Types ](https://www.iana.org/assignments/media-types)
- PDF &rarr; ISO 32000-1 / [Adobe PDF 1.7](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf); [qpdf docs](https://qpdf.readthedocs.io/en/stable/cli.html)
- OLE/CFB &rarr; [MS-CFB](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/53989ce4-7b05-4f8d-829b-d08d6148375b)
- OOXML / OPC &rarr; [ECMA-376](https://ecma-international.org/publications-and-standards/standards/ecma-376), [OPC overview](https://www.loc.gov/preservation/digital/formats/fdd/fdd000363.shtml)
- ZIP &rarr; [PKWARE APPNOTE.TXT](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)
- 
