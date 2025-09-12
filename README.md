# Workato Repository

---

# Workato Connector Template

## Quick Start
1. Run `chmod +x ./setup.sh`, then `./setup.sh`
2. Test: `make test`
3. Console: `make console`

## Structure
- `connectors/` - Your connector files
- `test/` - Test files
- `docker-compose.yml` - Local test services

## Commands
- `make help` - Show commands
- `make test CONNECTOR=name` - Test connector
- `docker-compose up -d` - Start test services
