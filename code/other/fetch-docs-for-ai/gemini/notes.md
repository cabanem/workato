## Objective
Fetch publicly available content from the Workato Connector SDK docs and make it usable by a Google AI model. 

## Options
### 1 - Vertex AI Search Website Crawl with Gemini Grounding
1. Create a website data store in AI Applications (Vertex AI Search)
   - In the GCP console, go to AI Applications &rarr; Create data store &rarr; Choose website
   - Enable `Advanced Website Indexing` and specify URL patterns
   ```
    https://docs.workato.com/developing-connectors/sdk*
    https://docs.workato.com/developing-connectors/sdk/*
    https://docs.workato.com/en/developing-connectors/sdk*https://docs.workato.com/en/developing-connectors/sdk/*
   ```
   - Avoid dynamic/application URLs and keep to the docs subdomain
2. Let Vertex AI Search index and refresh
3. Ground Gemini to that data store
    - In Vertex AI Studio, turn on `Grounding: your data` &rarr; select Vertex AI Search &rarr; Paste the data store path
    - Programatically:
    ```
    from google import genai
    from google.genai.types import GenerateContentConfig, HttpOptions, Retrieval, Tool, VertexAISearch

    client = genai.Client(http_options=HttpOptions(api_version="v1"))
    datastore = "projects/PROJECT_ID/locations/global/collections/default_collection/dataStores/DATA_STORE_ID"

    resp = client.models.generate_content(
        model="gemini-2.5-flash",
        contents="Summarize Workato's Connector SDK connection flow.",
        config=GenerateContentConfig(
            tools=[Tool(retrieval=Retrieval(vertex_ai_search=VertexAISearch(datastore=datastore)))]
        ),
    )
    print(resp.text)
    ```
    - Provide the expected datastore path format upon enabling
    ```
    projects/PROJECT_ID/locations/global/collections/default_collection/dataStores/DATA_STORE_ID
    ```
### 2 - Push HTML/Markdown to GCS and Index as 'Documents'
### 3 - Locally Push HTML/Markdown to GCS and Index as 'Documents'