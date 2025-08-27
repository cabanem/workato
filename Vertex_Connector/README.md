# Workato Connector: Google Vertex AI
## Existing Functionality
### Scope
Exposes a set of AI actions oriented around Google LLMs and the Vertex AI interface. 
**Out-of-the-box actions include:**
- Send messages to Gemini models
- Analyze text
- Analyze image
- Categorize text
- Summarize text
- Translate text
- Generate text embedding
- Parse text
- Get prediction

**Auth patterns worth keeping**
- Service account authentication (JWT)
- OAuth 2.0

### Additional Configuration
1. Unify on generative endpoint versions (`v1`, `v1beta`, etc)
2. Add streaming for generative content
   - Integrate a toggle, `Use streaming`
3. Expose full generation controls and structured outputs
4. Model discovery at runtime
5. Integrate distinct prediction types
   - Endpoint for custom deployed models
   - Publisher model (model garden)
6. Integrate translation and language detection
7. Improve error handling, retries
8. Chat history (context window)
9. Regional and quota awareness

## Implementation
1. Generate content (advanced, non-streaming)
   - REST
     - POST
     - `https://{location}-aiplatform.googleapis.com/v1/projects/{project}/locations/{location}/publishers/google/models/{model}:generateContent`
2. Predict (two endpoints, one action)
   - Expose a picklist/toggle, build the URL accordingly
3. Detect language (Cloud Translation v3)
   - REST
     - POST
     - `https://translation.googleapis.com/v3/projects/{project}/locations/global:detectLanguage`
   - Add the header, `x-goog-user-project: {project}`, when extending a service account.