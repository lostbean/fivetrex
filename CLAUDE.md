# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Commands

```bash
# Run all checks (format, credo, compile, test)
mix precommit

# Run CI checks (check-formatted, credo, compile, test + integration)
mix ci

# Run tests
mix test

# Run integration tests (requires .env with API credentials)
mix test --include integration

# Run a single test file
mix test test/fivetrex/client_test.exs

# Run a single test by line number
mix test test/fivetrex/client_test.exs:31

# Format code
mix format

# Run Credo (static analysis)
mix credo --strict

# Compile with warnings as errors
mix compile --warnings-as-errors

# Generate docs
mix docs
```

## Architecture

Fivetrex is an Elixir client library for the Fivetran REST API, built on Req.

### Module Structure

- `Fivetrex` - Entry point, provides `client/1` to create authenticated clients
- `Fivetrex.Client` - Low-level HTTP client handling auth (Basic), requests, and
  error mapping
- `Fivetrex.Stream` - Cursor-based pagination as lazy Elixir Streams via
  `Stream.resource/3`
- `Fivetrex.Error` - Structured error types (`:unauthorized`, `:not_found`,
  `:rate_limited`, `:server_error`)

### API Modules

Each API resource follows the same pattern with CRUD operations + `stream/2` for
pagination:

- `Fivetrex.Groups` - Group management
- `Fivetrex.Connectors` - Connector management + sync operations
- `Fivetrex.Destinations` - Destination warehouse management

### Models

Typed structs in `Fivetrex.Models.*` (Group, Connector, Destination) with helper
functions.

## Testing

Tests use Bypass to mock the Fivetran API. Test helpers are in
`test/test_helper.exs`:

- `client_with_bypass/1` - Creates a client pointing to Bypass
- `success_response/1`, `list_response/2`, `error_response/1` - Mock response
  builders
