# API Specification

## Base
- Protocol: HTTP
- Server: FastAPI
- Base path: `/`

## Endpoint: `POST /ask`
**Description**: Answers a question using the Workato Connector SDK docs.

### Request
- `Content-Type: application/json`
- Body:
```json
{
  "query": "How do I scaffold a new connector project?",
  "k": 8
}
```

### Response (200)
```json
{
  "query": "How do I scaffold a new connector project?",
  "answer": "You can use the CLI ...",
  "citations": [
    {"n":1,"url":"https://docs.workato.com/...", "score":0.81},
    {"n":2,"url":"https://docs.workato.com/...", "score":0.77}
  ],
  "contexts": [
    {"n":1,"url":"https://docs.workato.com/...","score":0.81},
    {"n":2,"url":"https://docs.workato.com/...","score":0.77}
  ]
}
```

### Errors
- **400**: missing or empty `query`
- **500**: index not available or internal error

### CLI
`python -m src.scripts.ask "question" [-k 8]`
