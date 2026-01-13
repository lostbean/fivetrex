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

  Create with Connect Card for OAuth flows:

      {:ok, connector} = Fivetrex.Connectors.create(client, %{
        group_id: "group_id",
        service: "google_analytics_4",
        connect_card_config: %{
          redirect_uri: "https://your.site/callback",
          hide_setup_guide: false
        }
      })

      # connector.connect_card will contain:
      # %{
      #   "token" => "eyJ0eXAiOiJKV1QiLCJh...",
      #   "uri" => "https://fivetran.com/connect-card/setup?auth=..."
      # }

      redirect_url = connector.connect_card["uri"]

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

  @typedoc """
  Result of a sync operation.

    * `:success` - Whether the sync was triggered successfully
    * `:message` - Optional message from the API
    * `:sync_state` - Current sync state after triggering (if available)
  """
  @type sync_result :: %{
          success: boolean(),
          message: String.t() | nil,
          sync_state: String.t() | nil
        }

  @doc """
  Triggers an incremental sync for a connector.

  This initiates a sync that only processes data that has changed since the
  last sync. The sync runs asynchronously; this function returns immediately.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector to sync

  ## Returns

    * `{:ok, sync_result()}` - Sync triggered successfully. Returns a map with:
      * `:success` - Always `true` on success
      * `:message` - Optional message from the API
      * `:sync_state` - Current sync state if available

    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, %{success: true}} = Fivetrex.Connectors.sync(client, "connector_id")

      # With full result inspection
      case Fivetrex.Connectors.sync(client, connector_id) do
        {:ok, %{success: true, sync_state: state}} ->
          IO.puts("Sync triggered, state: \#{state}")

        {:error, error} ->
          IO.puts("Sync failed: \#{error.message}")
      end

  """
  @spec sync(Client.t(), String.t()) :: {:ok, sync_result()} | {:error, Fivetrex.Error.t()}
  def sync(client, connector_id) do
    case Client.post(client, "/connectors/#{connector_id}/sync") do
      {:ok, response} ->
        {:ok, normalize_sync_response(response)}

      {:error, _} = error ->
        error
    end
  end

  defp normalize_sync_response(response) do
    %{
      success: response["code"] == "Success" or Map.has_key?(response, "data"),
      message: response["message"],
      sync_state: get_in(response, ["data", "status", "sync_state"])
    }
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

  # ===========================================================================
  # Schema Configuration Functions
  # ===========================================================================

  alias Fivetrex.Models.Column
  alias Fivetrex.Models.SchemaConfig

  @doc """
  Gets the schema configuration for a connector.

  Returns the current schema, table, and column configuration including
  enabled/disabled states and sync modes.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector

  ## Returns

    * `{:ok, SchemaConfig.t()}` - The schema configuration
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Note

  Only explicitly configured (non-default) columns are returned in this response.
  For a complete column list, use `get_table_columns/4`.

  ## Examples

      {:ok, config} = Fivetrex.Connectors.get_schema_config(client, "connector_id")

      # Iterate through schemas and tables
      for {schema_name, schema} <- config.schemas, schema.enabled do
        IO.puts("Schema: \#{schema_name}")

        for {table_name, table} <- schema.tables, table.enabled do
          IO.puts("  Table: \#{table_name} (sync_mode: \#{table.sync_mode})")
        end
      end

  """
  @spec get_schema_config(Client.t(), String.t()) ::
          {:ok, SchemaConfig.t()} | {:error, Fivetrex.Error.t()}
  def get_schema_config(client, connector_id) do
    case Client.get(client, "/connectors/#{connector_id}/schemas") do
      {:ok, %{"data" => data}} ->
        {:ok, SchemaConfig.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets the columns for a specific table in a connector.

  Returns the complete column list for a table, including columns using
  default settings (which may be omitted from `get_schema_config/2`).

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector
    * `schema_name` - The source schema name
    * `table_name` - The source table name

  ## Returns

    * `{:ok, %{String.t() => Column.t()}}` - Map of column name to Column struct
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, columns} = Fivetrex.Connectors.get_table_columns(
        client,
        "connector_id",
        "public",
        "users"
      )

      # Find primary key columns
      primary_keys =
        columns
        |> Enum.filter(fn {_name, col} -> col.is_primary_key end)
        |> Enum.map(fn {name, _col} -> name end)

      # Find hashed columns
      hashed =
        columns
        |> Enum.filter(fn {_name, col} -> col.hashed end)
        |> Enum.map(fn {name, _col} -> name end)

  """
  @spec get_table_columns(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, %{String.t() => Column.t()}} | {:error, Fivetrex.Error.t()}
  def get_table_columns(client, connector_id, schema_name, table_name) do
    path = "/connectors/#{connector_id}/schemas/#{schema_name}/tables/#{table_name}/columns"

    case Client.get(client, path) do
      {:ok, %{"data" => %{"columns" => columns}}} when is_map(columns) ->
        parsed =
          Map.new(columns, fn {name, data} ->
            {name, Column.from_map(data)}
          end)

        {:ok, parsed}

      {:ok, %{"data" => data}} when is_map(data) ->
        # Handle case where columns might be at the top level of data
        columns = Map.get(data, "columns", data)

        parsed =
          Map.new(columns, fn {name, col_data} ->
            {name, Column.from_map(col_data)}
          end)

        {:ok, parsed}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Updates the schema configuration for a connector.

  Use this to enable/disable schemas, tables, or columns, or to change
  sync modes and destination names.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector
    * `params` - A map with configuration updates:
      * `:schema_change_handling` - `"ALLOW_ALL"`, `"ALLOW_COLUMNS"`, or `"BLOCK_ALL"`
      * `:schemas` - Map of schema configurations to update

  ## Returns

    * `{:ok, SchemaConfig.t()}` - The updated schema configuration
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

  Disable a specific table:

      {:ok, config} = Fivetrex.Connectors.update_schema_config(client, "connector_id", %{
        schemas: %{
          "public" => %{
            tables: %{
              "sensitive_data" => %{enabled: false}
            }
          }
        }
      })

  Hash a column for privacy:

      {:ok, config} = Fivetrex.Connectors.update_schema_config(client, "connector_id", %{
        schemas: %{
          "public" => %{
            tables: %{
              "users" => %{
                columns: %{
                  "email" => %{hashed: true}
                }
              }
            }
          }
        }
      })

  Change schema change handling:

      {:ok, config} = Fivetrex.Connectors.update_schema_config(client, "connector_id", %{
        schema_change_handling: "BLOCK_ALL"
      })

  """
  @spec update_schema_config(Client.t(), String.t(), map()) ::
          {:ok, SchemaConfig.t()} | {:error, Fivetrex.Error.t()}
  def update_schema_config(client, connector_id, params) do
    case Client.patch(client, "/connectors/#{connector_id}/schemas", params) do
      {:ok, %{"data" => data}} ->
        {:ok, SchemaConfig.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Reloads the schema configuration from the source.

  This fetches the latest schema from the data source and updates the
  connector's schema configuration with any new schemas, tables, or columns.
  This can be slow for large schemas.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector
    * `opts` - Optional keyword list:
      * `:exclude_mode` - How to handle newly discovered items:
        * `"PRESERVE"` (default) - Keep existing enabled/disabled settings
        * `"INCLUDE"` - Enable all new schemas and tables
        * `"EXCLUDE"` - Disable all new schemas and tables

  ## Returns

    * `{:ok, SchemaConfig.t()}` - The reloaded schema configuration
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

  Reload with default settings:

      {:ok, config} = Fivetrex.Connectors.reload_schema_config(client, "connector_id")

  Reload and enable all new items:

      {:ok, config} = Fivetrex.Connectors.reload_schema_config(
        client,
        "connector_id",
        exclude_mode: "INCLUDE"
      )

  Reload and disable all new items:

      {:ok, config} = Fivetrex.Connectors.reload_schema_config(
        client,
        "connector_id",
        exclude_mode: "EXCLUDE"
      )

  """
  @spec reload_schema_config(Client.t(), String.t(), keyword()) ::
          {:ok, SchemaConfig.t()} | {:error, Fivetrex.Error.t()}
  def reload_schema_config(client, connector_id, opts \\ []) do
    body = if mode = opts[:exclude_mode], do: %{exclude_mode: mode}, else: %{}

    case Client.post(client, "/connectors/#{connector_id}/schemas/reload", body) do
      {:ok, %{"data" => data}} ->
        {:ok, SchemaConfig.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  # ===========================================================================
  # Sync Status and Frequency Functions
  # ===========================================================================

  alias Fivetrex.Models.SyncStatus

  @doc """
  Gets a summary of the connector's current sync status.

  Returns a structured view of the connector's sync state including
  last success/failure times. For detailed sync history, configure Fivetran's
  Log Service to send logs to your data warehouse.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector

  ## Returns

    * `{:ok, SyncStatus.t()}` - A struct containing:
      * `:sync_state` - Current state (e.g., `"syncing"`, `"scheduled"`)
      * `:succeeded_at` - Last successful sync timestamp
      * `:failed_at` - Last failed sync timestamp
      * `:is_historical_sync` - Whether a historical sync is in progress
      * `:update_state` - Update status

    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, status} = Fivetrex.Connectors.get_sync_status(client, "connector_id")
      IO.puts("Current state: \#{status.sync_state}")
      IO.puts("Last success: \#{status.succeeded_at}")

      if SyncStatus.syncing?(status) do
        IO.puts("Sync in progress...")
      end

  """
  @spec get_sync_status(Client.t(), String.t()) ::
          {:ok, SyncStatus.t()} | {:error, Fivetrex.Error.t()}
  def get_sync_status(client, connector_id) do
    case get(client, connector_id) do
      {:ok, connector} ->
        {:ok, SyncStatus.from_connector(connector)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Sets the sync frequency for a connector.

  A convenience function for updating sync timing configuration.

  ## Parameters

    * `client` - The Fivetrex client
    * `connector_id` - The ID of the connector
    * `frequency_minutes` - Sync frequency in minutes
    * `opts` - Optional keyword list:
      * `:schedule_type` - `"auto"` or `"manual"`
      * `:daily_sync_time` - Time for daily syncs (e.g., `"14:00"`)

  ## Returns

    * `{:ok, Connector.t()}` - The updated connector
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

  Set to sync every 60 minutes:

      {:ok, connector} = Fivetrex.Connectors.set_sync_frequency(client, "id", 60)

  Set daily sync at 2pm UTC:

      {:ok, connector} = Fivetrex.Connectors.set_sync_frequency(client, "id", 1440,
        schedule_type: "manual",
        daily_sync_time: "14:00"
      )

  """
  @spec set_sync_frequency(Client.t(), String.t(), pos_integer(), keyword()) ::
          {:ok, Connector.t()} | {:error, Fivetrex.Error.t()}
  def set_sync_frequency(client, connector_id, frequency_minutes, opts \\ []) do
    params =
      %{sync_frequency: frequency_minutes}
      |> maybe_put(:schedule_type, opts[:schedule_type])
      |> maybe_put(:daily_sync_time, opts[:daily_sync_time])

    update(client, connector_id, params)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp build_pagination_params(opts) do
    []
    |> maybe_add_param(:cursor, opts[:cursor])
    |> maybe_add_param(:limit, opts[:limit])
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: [{key, value} | params]
end
