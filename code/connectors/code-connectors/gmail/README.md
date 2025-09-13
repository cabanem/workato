# Gmail Connector (OAuth 2.0)
## What to set up in Google Cloud
Before creating the connector, prepare an OAuth client in your Google Cloud project.
1. Enable the Gmail API for the project.
2. Create OAuth 2.0 "web application" credentials. Add Workato's callback URL (region-specific).
3. Request the following scopes:
   - Read/headers: `https://www.googleapis.com/auth/gmail.readonly`, `https://www.googleapis.com/auth/gmail.metadata`
   - Modify: `https://www.googleapis.com/auth/gmail.modify`
   - Send: `https://www.googleapis.com/auth/gmail.send`

## Connector details
- Implements OAuth 2.0 over Google endpoints using appropriate scope handling.
- Uses least privilege by default
- Exposes useful API actions and methods applicable to the use case
- Normalizes common header fields and extracts plain-text / HTML bodies.