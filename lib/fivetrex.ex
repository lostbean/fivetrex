defmodule Fivetrex do
  @moduledoc """
  Elixir client library for the Fivetran REST API.

  Fivetrex provides a powerful, idiomatic Elixir interface for managing Fivetran
  resources including Groups, Connectors, and Destinations. Built on
  [Req](https://hexdocs.pm/req), it offers streaming pagination, structured error
  handling, and a clean functional API.

  ## Features

    * **Complete API Coverage** - Full CRUD operations for Groups, Connectors, and Destinations
    * **Stream-based Pagination** - Efficiently iterate over thousands of resources using Elixir Streams
    * **Typed Structs** - All responses are parsed into typed structs for compile-time safety
    * **Structured Errors** - Pattern-matchable error types for robust error handling
    * **Safety Valves** - Destructive operations like `resync!` require explicit confirmation

  ## Quick Start

  All API operations require a client configured with your Fivetran API credentials:

      # Create a client
      client = Fivetrex.client(
        api_key: System.get_env("FIVETRAN_API_KEY"),
        api_secret: System.get_env("FIVETRAN_API_SECRET")
      )

      # List all groups
      {:ok, %{items: groups}} = Fivetrex.Groups.list(client)

      # Get connectors in a group
      {:ok, %{items: connectors}} = Fivetrex.Connectors.list(client, "group_123")

      # Trigger a sync
      {:ok, _} = Fivetrex.Connectors.sync(client, "connector_abc")

  ## Streaming

  Use streams for efficient pagination over large result sets. Streams handle
  Fivetran's cursor-based pagination transparently:

      # Stream all groups
      client
      |> Fivetrex.Groups.stream()
      |> Enum.each(&IO.inspect/1)

      # Find all syncing connectors across all groups
      client
      |> Fivetrex.Groups.stream()
      |> Stream.flat_map(fn group ->
        Fivetrex.Connectors.stream(client, group.id)
      end)
      |> Stream.filter(&Fivetrex.Models.Connector.syncing?/1)
      |> Enum.to_list()

  ## Error Handling

  All API functions return `{:ok, result}` on success or `{:error, %Fivetrex.Error{}}`
  on failure. Errors are structured for easy pattern matching:

      case Fivetrex.Connectors.get(client, "connector_id") do
        {:ok, connector} ->
          IO.puts("Found: \#{connector.id}")

        {:error, %Fivetrex.Error{type: :not_found}} ->
          IO.puts("Connector not found")

        {:error, %Fivetrex.Error{type: :rate_limited, retry_after: seconds}} ->
          IO.puts("Rate limited, retry after \#{seconds} seconds")
      end

  ## Modules

    * `Fivetrex.Groups` - Manage Fivetran groups
    * `Fivetrex.Connectors` - Manage connectors and sync operations
    * `Fivetrex.Destinations` - Manage destination warehouses
    * `Fivetrex.Client` - Low-level HTTP client
    * `Fivetrex.Error` - Structured error types
    * `Fivetrex.Stream` - Pagination utilities
    * `Fivetrex.Retry` - Retry with exponential backoff for transient failures

  ## Model Structs

    * `Fivetrex.Models.Group` - Group resource
    * `Fivetrex.Models.Connector` - Connector resource
    * `Fivetrex.Models.Destination` - Destination resource
  """

  alias Fivetrex.Client

  @doc """
  Creates a new Fivetrex client with the given credentials.

  The client is used for all API operations and contains authentication
  information and HTTP configuration. You can create multiple clients
  to work with different Fivetran accounts.

  ## Options

    * `:api_key` - Required. Your Fivetran API key. Generate one from
      your Fivetran dashboard under Settings > API Key.

    * `:api_secret` - Required. Your Fivetran API secret. This is shown
      only once when you generate the API key.

    * `:base_url` - Optional. Override the API base URL. Defaults to
      `https://api.fivetran.com/v1`. Useful for testing with mock servers.

  ## Examples

  Create a client with explicit credentials:

      client = Fivetrex.client(
        api_key: "your_api_key",
        api_secret: "your_api_secret"
      )

  Create a client using environment variables:

      client = Fivetrex.client(
        api_key: System.get_env("FIVETRAN_API_KEY"),
        api_secret: System.get_env("FIVETRAN_API_SECRET")
      )

  Create a client for testing with a custom base URL:

      client = Fivetrex.client(
        api_key: "test",
        api_secret: "test",
        base_url: "http://localhost:4000"
      )

  ## Raises

    * `KeyError` - If `:api_key` or `:api_secret` is not provided

  """
  @spec client(keyword()) :: Client.t()
  def client(opts) do
    Client.new(opts)
  end
end
