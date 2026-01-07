# Fivetrex

[![Hex.pm](https://img.shields.io/hexpm/v/fivetrex.svg)](https://hex.pm/packages/fivetrex)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/fivetrex)

Elixir client library for the [Fivetran REST API](https://fivetran.com/docs/rest-api).

Fivetrex provides a powerful, idiomatic Elixir interface for managing Fivetran resources including Groups, Connectors, and Destinations. Built on [Req](https://hexdocs.pm/req), it offers streaming pagination, structured error handling, and a clean functional API.

## Features

- **Complete API Coverage** - Full CRUD operations for Groups, Connectors, and Destinations
- **Stream-based Pagination** - Efficiently iterate over thousands of resources using Elixir Streams
- **Typed Structs** - All responses are parsed into typed structs for compile-time safety
- **Structured Errors** - Pattern-matchable error types for robust error handling
- **Safety Valves** - Destructive operations like `resync!` require explicit confirmation
- **Zero Configuration** - Works out of the box with just API credentials

## Installation

Add `fivetrex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:fivetrex, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Creating a Client

All API operations require a client configured with your Fivetran API credentials:

```elixir
# Create a client with explicit credentials
client = Fivetrex.client(
  api_key: "your_api_key",
  api_secret: "your_api_secret"
)

# Or use environment variables
client = Fivetrex.client(
  api_key: System.get_env("FIVETRAN_API_KEY"),
  api_secret: System.get_env("FIVETRAN_API_SECRET")
)
```

### Basic Operations

```elixir
# List all groups
{:ok, %{items: groups, next_cursor: _}} = Fivetrex.Groups.list(client)

# Get a specific group
{:ok, group} = Fivetrex.Groups.get(client, "group_id")

# Create a new group
{:ok, group} = Fivetrex.Groups.create(client, %{name: "My Data Warehouse"})

# List connectors in a group
{:ok, %{items: connectors}} = Fivetrex.Connectors.list(client, group.id)

# Trigger a sync
{:ok, _} = Fivetrex.Connectors.sync(client, "connector_id")

# Pause and resume connectors
{:ok, _} = Fivetrex.Connectors.pause(client, "connector_id")
{:ok, _} = Fivetrex.Connectors.resume(client, "connector_id")
```

## Streaming

Fivetrex uses Elixir Streams to handle Fivetran's cursor-based pagination transparently. This allows you to iterate over thousands of resources without loading them all into memory:

```elixir
# Stream all groups
client
|> Fivetrex.Groups.stream()
|> Enum.each(fn group ->
  IO.puts("Group: #{group.name}")
end)

# Find all syncing connectors across all groups
syncing_connectors =
  client
  |> Fivetrex.Groups.stream()
  |> Stream.flat_map(fn group ->
    Fivetrex.Connectors.stream(client, group.id)
  end)
  |> Stream.filter(&Fivetrex.Models.Connector.syncing?/1)
  |> Enum.to_list()

# Take only the first 10 broken connectors
broken =
  Fivetrex.Connectors.stream(client, "group_id")
  |> Stream.filter(fn c -> c.status["sync_state"] == "broken" end)
  |> Enum.take(10)
```

## Working with Connectors

### Creating a Connector

```elixir
{:ok, connector} = Fivetrex.Connectors.create(client, %{
  group_id: "group_id",
  service: "postgres",
  config: %{
    host: "db.example.com",
    port: 5432,
    database: "production",
    user: "fivetran_user",
    password: "secret"
  }
})
```

### Sync Operations

```elixir
# Trigger an incremental sync
{:ok, _} = Fivetrex.Connectors.sync(client, connector.id)

# Get current sync state
{:ok, state} = Fivetrex.Connectors.get_state(client, connector.id)

# Historical resync (DANGEROUS - requires confirmation)
# This wipes all data and re-imports from scratch
{:ok, _} = Fivetrex.Connectors.resync!(client, connector.id, confirm: true)
```

### Connector Helper Functions

```elixir
alias Fivetrex.Models.Connector

# Check connector status
Connector.syncing?(connector)   # => true/false
Connector.paused?(connector)    # => true/false
Connector.sync_state(connector) # => "scheduled" | "syncing" | "paused" | nil
```

## Working with Destinations

```elixir
# Get a destination
{:ok, destination} = Fivetrex.Destinations.get(client, "destination_id")

# Create a Snowflake destination
{:ok, destination} = Fivetrex.Destinations.create(client, %{
  group_id: "group_id",
  service: "snowflake",
  region: "US",
  time_zone_offset: "-5",
  config: %{
    host: "account.snowflakecomputing.com",
    port: 443,
    database: "ANALYTICS",
    auth: "PASSWORD",
    user: "FIVETRAN_USER",
    password: "secret"
  }
})

# Test destination connectivity
{:ok, result} = Fivetrex.Destinations.test(client, destination.id)
```

## Error Handling

All API functions return `{:ok, result}` on success or `{:error, %Fivetrex.Error{}}` on failure. Errors are structured for easy pattern matching:

```elixir
case Fivetrex.Connectors.get(client, "connector_id") do
  {:ok, connector} ->
    # Success - connector is a %Fivetrex.Models.Connector{}
    IO.puts("Found connector: #{connector.id}")

  {:error, %Fivetrex.Error{type: :not_found}} ->
    # 404 - Resource doesn't exist
    IO.puts("Connector not found")

  {:error, %Fivetrex.Error{type: :unauthorized}} ->
    # 401 - Invalid API credentials
    IO.puts("Check your API key and secret")

  {:error, %Fivetrex.Error{type: :rate_limited, retry_after: seconds}} ->
    # 429 - Too many requests
    IO.puts("Rate limited, retry after #{seconds} seconds")
    Process.sleep(seconds * 1000)
    # Retry...

  {:error, %Fivetrex.Error{type: :server_error, status: status}} ->
    # 5xx - Fivetran server error
    IO.puts("Server error: #{status}")

  {:error, %Fivetrex.Error{message: message}} ->
    # Catch-all for other errors
    IO.puts("Error: #{message}")
end
```

### Error Types

| Type | HTTP Status | Description |
|------|-------------|-------------|
| `:unauthorized` | 401 | Invalid or missing API credentials |
| `:not_found` | 404 | Resource does not exist |
| `:rate_limited` | 429 | Too many requests (check `retry_after`) |
| `:server_error` | 5xx | Fivetran server error |
| `:unknown` | Other | Unexpected error |

## API Reference

### Groups

| Function | Description |
|----------|-------------|
| `Fivetrex.Groups.list/2` | List all groups with pagination |
| `Fivetrex.Groups.stream/2` | Stream all groups (handles pagination) |
| `Fivetrex.Groups.get/2` | Get a group by ID |
| `Fivetrex.Groups.create/2` | Create a new group |
| `Fivetrex.Groups.update/3` | Update a group |
| `Fivetrex.Groups.delete/2` | Delete a group |

### Connectors

| Function | Description |
|----------|-------------|
| `Fivetrex.Connectors.list/3` | List connectors in a group |
| `Fivetrex.Connectors.stream/3` | Stream all connectors in a group |
| `Fivetrex.Connectors.get/2` | Get a connector by ID |
| `Fivetrex.Connectors.create/2` | Create a new connector |
| `Fivetrex.Connectors.update/3` | Update a connector |
| `Fivetrex.Connectors.delete/2` | Delete a connector |
| `Fivetrex.Connectors.sync/2` | Trigger an incremental sync |
| `Fivetrex.Connectors.resync!/3` | Trigger a historical resync (destructive!) |
| `Fivetrex.Connectors.get_state/2` | Get connector sync state |
| `Fivetrex.Connectors.pause/2` | Pause a connector |
| `Fivetrex.Connectors.resume/2` | Resume a paused connector |

### Destinations

| Function | Description |
|----------|-------------|
| `Fivetrex.Destinations.get/2` | Get a destination by ID |
| `Fivetrex.Destinations.create/2` | Create a new destination |
| `Fivetrex.Destinations.update/3` | Update a destination |
| `Fivetrex.Destinations.delete/2` | Delete a destination |
| `Fivetrex.Destinations.test/2` | Run destination connection tests |

## Configuration

### Runtime Configuration

Fivetrex is designed for runtime configuration. Create clients with credentials at runtime rather than compile-time:

```elixir
# In your application code
defmodule MyApp.Fivetran do
  def client do
    Fivetrex.client(
      api_key: Application.get_env(:my_app, :fivetran_api_key),
      api_secret: Application.get_env(:my_app, :fivetran_api_secret)
    )
  end
end

# In config/runtime.exs
config :my_app,
  fivetran_api_key: System.get_env("FIVETRAN_API_KEY"),
  fivetran_api_secret: System.get_env("FIVETRAN_API_SECRET")
```

### Testing with Custom Base URL

For testing, you can override the base URL:

```elixir
client = Fivetrex.client(
  api_key: "test",
  api_secret: "test",
  base_url: "http://localhost:4000"
)
```

## Testing

Fivetrex uses [Bypass](https://hexdocs.pm/bypass) for integration testing. See the test suite for examples of mocking Fivetran API responses.

```bash
# Run tests
mix test

# Run tests with coverage
mix test --cover
```

## Documentation

Generate documentation locally:

```bash
mix docs
open doc/index.html
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Create a new Pull Request

## License

MIT License. See [LICENSE](LICENSE) for details.

## Links

- [Fivetran REST API Documentation](https://fivetran.com/docs/rest-api)
- [Fivetran API Reference](https://fivetran.com/docs/rest-api/api-reference)
- [HexDocs](https://hexdocs.pm/fivetrex)
