# GCP IAM Requirements

## Service Account
- Create a service account dedicated to accessing this connector

## Resource Scope
Permissions must be granted at the project level. The connector configuration requires:
- Project ID
- Region (location)
- API version (defaults to v1)

## Method of Access

### Method 1: Predefined Role
`Vertex AI User` (`roles/aiplatform.user)

### Method 2: Granular Permissions
**Core**
| Role | Description | 
| :--- | :------------|
| `aiplatform.endpoints.predict` | Make predictions against deployed models |
| `aiplatform.publishers.get` | Access publisher models (Gemini, text-bison) |
| `aiplatform.datasets.get` | Read dataset metadata (used for connection testing) |
| `aiplatform.datasets.list` | List datasets in a project/location |
| `aiplatform.locations.get` | Get location information |
| `aiplatform.locations.list` | List available locations |
| `aiplatform.models.predict` | Make predictions using models |
| `aiplatform.endpoints.list` | List available endpoints |