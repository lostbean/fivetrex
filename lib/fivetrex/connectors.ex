defmodule Fivetrex.Connectors do
  @moduledoc """
  Functions for managing Fivetran Connectors.

  A Connector is the core operational entity in Fivetran, representing the pipe
  between a data source (e.g., Salesforce, PostgreSQL, Google Ads) and a
  destination warehouse. This module provides functions for CRUD operations
  as well as sync control.

  ## Overview

  Connectors handle the actual data movement. Each connector:
    * Belongs to a single group
    * Connects to a specific data source type (service)
    * Has configuration specific to that service type
    * Maintains sync state and schedule

  ## Connector States

  Connectors have various states tracked in the `status` field:

    * `"scheduled"` - Waiting for next sync
    * `"syncing"` - Currently syncing data
    * `"paused"` - Manually paused
    * `"rescheduled"` - Sync was rescheduled

  Use helper functions on `Fivetrex.Models.Connector` to check state:

      Connector.syncing?(connector)  # => true/false
      Connector.paused?(connector)   # => true/false

  ## Common Operations

  ### List Connectors in a Group

      {:ok, %{items: connectors}} = Fivetrex.Connectors.list(client, "group_id")

  ### Get a Connector

      {:ok, connector} = Fivetrex.Connectors.get(client, "connector_id")

  ### Trigger a Sync

      {:ok, _} = Fivetrex.Connectors.sync(client, "connector_id")

  ### Pause/Resume

      {:ok, _} = Fivetrex.Connectors.pause(client, "connector_id")
      {:ok, _} = Fivetrex.Connectors.resume(client, "connector_id")

  ## Dangerous Operations

  The `resync!/3` function triggers a historical resync, which wipes all synced
  data and re-imports from scratch. This can be expensive and time-consuming.
  It requires explicit confirmation:

      {:ok, _} = Fivetrex.Connectors.resync!(client, "connector_id", confirm: true)

  ## See Also

    * `Fivetrex.Models.Connector` - The Connector struct with helper functions
    * `Fivetrex.Groups` - Managing the parent groups
  """

  alias Fivetrex.Client
  alias Fivetrex.Models.Connector

  @doc """
  Lists all connectors in a group.

  Returns a paginated list of connectors belonging to the specified group.

  ## Parameters

    * `client` - The Fivetrex client
    * `group_id` - The ID of the group to list connectors from
    * `opts` - Optional keyword list:
      * `:cursor` - Pagination cursor from a previous response
      * `:limit` - Maximum items per page (max 1000)

  ## Returns

    * `{:ok, %{items: [Connector.t()], next_cursor: String.t() | nil}}` - Success
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, %{items: connectors, next_cursor: cursor}} =
        Fivetrex.Connectors.list(client, "group_id")

      # Check connector states
      syncing = Enum.filter(connectors, &Connector.syncing?/1)

  """
  @spec list(Client.t(), String.t(), keyword()) ::
          {:ok, %{items: [Connector.t()], next_cursor: String.t() | nil}}
          | {:error, Fivetrex.Error.t()}
  def list(client, group_id, opts \\ []) do
    params = build_pagination_params(opts)

    case Client.get(client, "/groups/#{group_id}/connectors", params: params) do
      {:ok, %{"data" => %{"items" => items, "next_cursor" => next_cursor}}} ->
        connectors = Enum.map(items, &Connector.from_map/1)
        {:ok, %{items: connectors, next_cursor: next_cursor}}

      {:ok, %{"data" => %{"items" => items}}} ->
        connectors = Enum.map(items, &Connector.from_map/1)
        {:ok, %{items: connectors, next_cursor: nil}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Returns a stream of all connectors in a group, handling pagination automatically.

  This is memory-efficient for groups with many connectors.

  ## Parameters

    * `client` - The Fivetrex client
    * `group_id` - The ID of the group
    * `opts` - Options passed to each `list/3` call

  ## Returns

  An `Enumerable.t()` yielding `%Fivetrex.Models.Connector{}` structs.

  ## Examples

      # Find all syncing connectors
      syncing =
        Fivetrex.Connectors.stream(client, "group_id")
        |> Stream.filter(&Connector.syncing?/1)
        |> Enum.to_list()

      # Process connectors one at a time
      Fivetrex.Connectors.stream(client, "group_id")
      |> Enum.each(&process_connector/1)

  """
  @spec stream(Client.t(), String.t(), keyword()) :: Enumerable.t()
  def stream(client, group_id, opts \\ []) do
    Fivetrex.Stream.paginate(fn cursor ->
      list(client, group_id, Keyword.put(opts, :cursor, cursor))
    end)
  end

  @doc """
  Gets a connector by its ID.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The unique identifier of the connector

  ## Returns

    * `{:ok, Connector.t()}` - The connector
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, connector} = Fivetrex.Connectors.get(client, "connector_id")
      IO.puts("Service: \#{connector.service}")
      IO.puts("Syncing: \#{Connector.syncing?(connector)}")

  """
  @spec get(Client.t(), String.t()) :: {:ok, Connector.t()} | {:error, Fivetrex.Error.t()}
  def get(client, connector_id) do
    case Client.get(client, "/connectors/#{connector_id}") do
      {:ok, %{"data" => data}} ->
        {:ok, Connector.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Creates a new connector.

  The connector configuration is highly dependent on the service type. See
  Fivetran's documentation for service-specific configuration options.

  ## Parameters

    * `client` - The Fivetrex client
    * `params` - A map containing:
      * `:group_id` - Required. The group to create the connector in.
      * `:service` - Required. The connector type (e.g., "postgres", "salesforce").
      * `:config` - Required. Service-specific configuration map.
      * `:paused` - Optional. Start in paused state (default: false).
      * `:sync_frequency` - Optional. Sync frequency in minutes.

  ## Returns

    * `{:ok, Connector.t()}` - The created connector
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

  Create a PostgreSQL connector:

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

  Create a paused connector:

      {:ok, connector} = Fivetrex.Connectors.create(client, %{
        group_id: "group_id",
        service: "salesforce",
        paused: true,
        config: %{...}
      })

  """
  @spec create(Client.t(), map()) :: {:ok, Connector.t()} | {:error, Fivetrex.Error.t()}
  def create(client, params) do
    case Client.post(client, "/connectors", params) do
      {:ok, %{"data" => data}} ->
        {:ok, Connector.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Updates an existing connector.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector to update
    * `params` - A map with fields to update:
      * `:paused` - Pause or resume the connector
      * `:sync_frequency` - Sync frequency in minutes
      * `:config` - Updated configuration (merged with existing)

  ## Returns

    * `{:ok, Connector.t()}` - The updated connector
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, connector} = Fivetrex.Connectors.update(client, "connector_id", %{
        paused: true,
        sync_frequency: 60
      })

  """
  @spec update(Client.t(), String.t(), map()) ::
          {:ok, Connector.t()} | {:error, Fivetrex.Error.t()}
  def update(client, connector_id, params) do
    case Client.patch(client, "/connectors/#{connector_id}", params) do
      {:ok, %{"data" => data}} ->
        {:ok, Connector.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Deletes a connector.

  **Warning:** This permanently deletes the connector and all its sync history.
  The synced data in your destination is not affected.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector to delete

  ## Returns

    * `:ok` - On successful deletion
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      :ok = Fivetrex.Connectors.delete(client, "old_connector_id")

  """
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Fivetrex.Error.t()}
  def delete(client, connector_id) do
    case Client.delete(client, "/connectors/#{connector_id}") do
      {:ok, _} ->
        :ok

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Triggers an incremental sync for a connector.

  This initiates a sync that only processes data that has changed since the
  last sync. The sync runs asynchronously; this function returns immediately.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector to sync

  ## Returns

    * `{:ok, map()}` - Sync triggered successfully
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, _} = Fivetrex.Connectors.sync(client, "connector_id")

  """
  @spec sync(Client.t(), String.t()) :: {:ok, map()} | {:error, Fivetrex.Error.t()}
  def sync(client, connector_id) do
    case Client.post(client, "/connectors/#{connector_id}/sync") do
      {:ok, %{"data" => data}} ->
        {:ok, data}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Triggers a historical resync for a connector.

  **WARNING: This is a destructive operation!**

  A historical resync:
    * Wipes all of the connector's sync state
    * Re-imports ALL data from the source from scratch
    * Can take a very long time for large data sources
    * May incur significant costs (both Fivetran and source API costs)

  The `confirm: true` option is **required** to prevent accidental invocation.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector to resync
    * `opts` - Keyword list:
      * `:confirm` - **Required.** Must be `true` to confirm the operation.

  ## Returns

    * `{:ok, map()}` - Resync triggered successfully
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Raises

    * `ArgumentError` - If `confirm: true` is not provided

  ## Examples

      # This will raise ArgumentError:
      Fivetrex.Connectors.resync!(client, "connector_id", [])

      # This works:
      {:ok, _} = Fivetrex.Connectors.resync!(client, "connector_id", confirm: true)

  """
  @spec resync!(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Fivetrex.Error.t()}
  def resync!(client, connector_id, opts) do
    unless Keyword.get(opts, :confirm) == true do
      raise ArgumentError,
            "resync! is a destructive operation that will re-import all data. " <>
              "Pass `confirm: true` to confirm you want to proceed."
    end

    case Client.post(client, "/connectors/#{connector_id}/resync") do
      {:ok, %{"data" => data}} ->
        {:ok, data}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets the current state of a connector.

  Returns detailed sync state information including cursor positions, which
  can be useful for debugging sync issues.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector

  ## Returns

    * `{:ok, map()}` - The connector state as a raw map
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, state} = Fivetrex.Connectors.get_state(client, "connector_id")
      IO.inspect(state["state"])

  """
  @spec get_state(Client.t(), String.t()) :: {:ok, map()} | {:error, Fivetrex.Error.t()}
  def get_state(client, connector_id) do
    case Client.get(client, "/connectors/#{connector_id}/state") do
      {:ok, %{"data" => data}} ->
        {:ok, data}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Pauses a connector.

  A paused connector will not sync until resumed. This is a convenience
  function that calls `update/3` with `paused: true`.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector to pause

  ## Returns

    * `{:ok, Connector.t()}` - The paused connector
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, connector} = Fivetrex.Connectors.pause(client, "connector_id")
      true = Connector.paused?(connector)

  """
  @spec pause(Client.t(), String.t()) :: {:ok, Connector.t()} | {:error, Fivetrex.Error.t()}
  def pause(client, connector_id) do
    update(client, connector_id, %{paused: true})
  end

  @doc """
  Resumes a paused connector.

  This is a convenience function that calls `update/3` with `paused: false`.
  The connector will begin syncing according to its schedule.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector to resume

  ## Returns

    * `{:ok, Connector.t()}` - The resumed connector
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, connector} = Fivetrex.Connectors.resume(client, "connector_id")
      false = Connector.paused?(connector)

  """
  @spec resume(Client.t(), String.t()) :: {:ok, Connector.t()} | {:error, Fivetrex.Error.t()}
  def resume(client, connector_id) do
    update(client, connector_id, %{paused: false})
  end

  defp build_pagination_params(opts) do
    []
    |> maybe_add_param(:cursor, opts[:cursor])
    |> maybe_add_param(:limit, opts[:limit])
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: [{key, value} | params]
end
