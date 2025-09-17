# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Workato connector development repository using the Workato Connector SDK. The project focuses on building custom connectors for various services including Google Vertex AI, Gmail, and other utilities.

## Development Commands

### Setup and Installation
- `./setup.sh` - Initial setup and gem installation
- `chmod +x ./setup.sh` - Make setup script executable (if needed)
- `bundle install` - Install Ruby dependencies

### Testing and Validation
- `make test` - Test the default sample connector
- `make test CONNECTOR=connector_name` - Test a specific connector (without .rb extension)
- `ruby -c code/connectors/connector_name.rb` - Syntax check a connector file
- `workato exec check code/connectors/connector_name.rb` - Validate connector using Workato SDK

### Development Tools
- `make console` - Launch Workato console for default connector
- `make console CONNECTOR=connector_name` - Launch console for specific connector
- `workato exec console code/connectors/connector_name.rb` - Direct console access

### Utility Commands
- `make help` - Show available make commands
- `make clean` - Remove temporary files and logs
- `docker-compose up -d` - Start mock API services for testing

## Code Architecture

### Directory Structure
- `code/connectors/` - Main connector implementations
  - `vertex/` - Google Vertex AI connector with authentication options
  - `gmail/` - Gmail connector with OAuth2 implementation
  - `rag-utility/` - RAG (Retrieval Augmented Generation) utilities
  - `other/` - Shared utilities for data manipulation
- `code/other/` - Additional utilities and helper scripts
  - `send-encoded-file/` - File encoding and transmission utilities
  - `fetch-docs-for-ai/` - Documentation retrieval tools

### Connector Structure
Connectors are Ruby hashes defining:
- `title` - Display name for the connector
- `connection` - Authentication and configuration fields
- `custom_action` - Support for custom HTTP actions
- Actions, triggers, and object definitions specific to each service

### Key Technologies
- **Workato Connector SDK** - Primary framework for connector development
- **Ruby** - Implementation language
- **OAuth2** - Authentication mechanism for Google services
- **Docker** - Mock services for testing

## Testing Infrastructure

The repository includes comprehensive testing support:
- RSpec for unit testing
- VCR for HTTP interaction recording
- WebMock for HTTP request stubbing
- Docker-based mock API services

## Authentication Patterns

Connectors implement various authentication methods:
- **OAuth2** - Used for Gmail and other Google services with scope-based permissions
- **Service Account** - For Vertex AI with JSON key files
- **API Keys** - For simpler service integrations

## Development Workflow

1. Create new connectors in `code/connectors/[service_name]/`
2. Use existing connectors as templates for structure and patterns
3. Test connectors using `make test CONNECTOR=connector_name`
4. Use console for interactive development: `make console CONNECTOR=connector_name`
5. Validate syntax and structure before committing changes

## Important Notes

- Connector files should be named consistently (e.g., `vertex_connector.rb`)
- Authentication credentials should never be hardcoded
- Use the Workato SDK's built-in helpers for common operations
- Test with mock services before connecting to real APIs
- Follow the existing code patterns for consistency across connectors