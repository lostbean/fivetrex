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
    * **Built-in Retry** - Automatic retry with exponential backoff for transient failures
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

  ## Handling Rate Limits and Transient Errors

  Use `Fivetrex.with_retry/2` to automatically retry on rate limits and server errors:

      # Retry with default settings (3 attempts, exponential backoff)
      {:ok, %{items: groups}} = Fivetrex.with_retry(fn ->
        Fivetrex.Groups.list(client)
      end)

      # Custom retry options
      {:ok, connector} = Fivetrex.with_retry(
        fn -> Fivetrex.Connectors.get(client, "connector_id") end,
        max_attempts: 5,
        jitter: true
      )

      # With retry logging
      {:ok, _} = Fivetrex.with_retry(
        fn -> Fivetrex.Connectors.sync(client, connector_id) end,
        on_retry: fn error, attempt, delay ->
          Logger.warning("Retry \#{attempt}: \#{error.message}, waiting \#{delay}ms")
        end
      )

  The retry mechanism:
    * Automatically retries on `:rate_limited` and `:server_error` errors
    * Respects Fivetran's `retry-after` header for rate limits
    * Uses exponential backoff (1s, 2s, 4s, ...) capped at 30 seconds
    * Does NOT retry on `:unauthorized`, `:not_found`, or `:unknown` errors

  See `Fivetrex.Retry` for advanced configuration options.

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
  alias Fivetrex.Retry

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

  @doc """
  Executes a function with automatic retry and exponential backoff.

  This is a convenience wrapper around `Fivetrex.Retry.with_backoff/2`. Use it
  to handle transient failures like rate limits and server errors automatically.

  ## Parameters

    * `func` - A zero-arity function that returns `{:ok, result}` or `{:error, %Fivetrex.Error{}}`
    * `opts` - Optional keyword list:
      * `:max_attempts` - Maximum number of attempts (default: 3)
      * `:base_delay_ms` - Initial delay in milliseconds (default: 1000)
      * `:max_delay_ms` - Maximum delay cap in milliseconds (default: 30000)
      * `:jitter` - Add random jitter to delays (default: false)
      * `:retry_if` - Custom function to determine if error is retryable
      * `:on_retry` - Callback function called before each retry

  ## Returns

    * `{:ok, result}` - The successful result from `func`
    * `{:error, %Fivetrex.Error{}}` - The last error after all retries exhausted

  ## Examples

      # Basic usage - retry Groups.list on rate limits
      {:ok, %{items: groups}} = Fivetrex.with_retry(fn ->
        Fivetrex.Groups.list(client)
      end)

      # With custom options
      {:ok, connector} = Fivetrex.with_retry(
        fn -> Fivetrex.Connectors.get(client, "connector_id") end,
        max_attempts: 5,
        jitter: true
      )

      # With logging callback
      {:ok, _} = Fivetrex.with_retry(
        fn -> Fivetrex.Connectors.sync(client, connector_id) end,
        on_retry: fn error, attempt, delay ->
          IO.puts("Retry \#{attempt} after \#{delay}ms: \#{error.message}")
        end
      )

  ## Retryable Errors

  By default, these error types are retried:
    * `:rate_limited` - Respects `retry_after` header when available
    * `:server_error` - 5xx errors are typically transient

  Non-retryable errors (returned immediately):
    * `:unauthorized` - Invalid credentials won't become valid
    * `:not_found` - Resource doesn't exist
    * `:unknown` - Unexpected errors need investigation

  """
  @spec with_retry((-> {:ok, any()} | {:error, Fivetrex.Error.t()}), Retry.retry_opts()) ::
          {:ok, any()} | {:error, Fivetrex.Error.t()}
  def with_retry(func, opts \\ []) do
    Retry.with_backoff(func, opts)
  end
end
