# Security & Privacy

## 1. Threat Model
- **Scraping risk**: site may rate-limit; use polite crawl and scope restrictions.
- **Prompt injection**: context may contain adversarial text; system prompt instructs to only use provided context.
- **LLM exfiltration**: queries + contexts may be sent to provider; ensure provider terms are acceptable.

## 2. Controls
- Robots.txt respect; domain/path allowlist; file-type blocklist.
- Context-only answering guardrail; consider minimum similarity threshold (e.g., 0.3) to refuse low-confidence answers.
- Configurable provider; ability to run with Noop model for offline testing.

## 3. Data Handling
- Stores public docs content locally.
- Logs avoid sensitive data; truncate queries in logs if needed.
- Document attribution included in outputs.

## 4. Compliance Notes
- Review site Terms of Service before bulk ingestion.
- Provide clear source citations in responses.
