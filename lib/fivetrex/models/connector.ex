defmodule Fivetrex.Models.Connector do
  @moduledoc """
  Represents a Fivetran Connector.

  A Connector is the core operational entity in Fivetran, representing the
  pipeline between a data source (e.g., Salesforce, PostgreSQL, Google Ads)
  and a destination warehouse. Connectors handle the actual data extraction,
  transformation, and loading (ELT).

  ## Fields

    * `:id` - The unique identifier for the connector
    * `:group_id` - The ID of the parent group
    * `:service` - The connector type (e.g., `"postgres"`, `"salesforce"`, `"google_ads"`)
    * `:service_version` - The version number of the connector service
    * `:schema` - The destination schema/dataset name
    * `:paused` - Whether the connector is paused
    * `:pause_after_trial` - Whether to pause after free trial ends
    * `:sync_frequency` - Sync interval in minutes
    * `:status` - A map containing sync state and timing information
    * `:setup_state` - Setup status (e.g., `"connected"`, `"incomplete"`)
    * `:created_at` - ISO 8601 timestamp of creation
    * `:succeeded_at` - ISO 8601 timestamp of last successful sync
    * `:failed_at` - ISO 8601 timestamp of last failed sync
    * `:config` - Service-specific configuration (connection details, etc.)

  ## Status Map

  The `:status` field contains detailed sync information:

  ```elixir
  %{
    "sync_state" => "scheduled",     # Current state
    "update_state" => "on_schedule", # Update status
    "is_historical_sync" => false,   # Historical sync in progress?
    "tasks" => [...],                # Active tasks
    "warnings" => [...]              # Any warnings
  }
  ```

  ## Sync States

  The `sync_state` within the status map can be:

    * `"scheduled"` - Waiting for next scheduled sync
    * `"syncing"` - Currently syncing data
    * `"paused"` - Manually paused
    * `"rescheduled"` - Sync was rescheduled

  ## Helper Functions

  This module provides helper functions to check connector state:

      if Connector.syncing?(connector) do
        IO.puts("Sync in progress...")
      end

      if Connector.paused?(connector) do
        IO.puts("Connector is paused")
      end

  ## Examples

  Working with a connector:

      {:ok, connector} = Fivetrex.Connectors.get(client, "connector_id")
      IO.puts("Service: \#{connector.service}")
      IO.puts("Schema: \#{connector.schema}")
      IO.puts("Sync state: \#{Connector.sync_state(connector)}")

  Filtering connectors by state:

      {:ok, %{items: connectors}} = Fivetrex.Connectors.list(client, group_id)

      syncing = Enum.filter(connectors, &Connector.syncing?/1)
      paused = Enum.filter(connectors, &Connector.paused?/1)

  ## See Also

    * `Fivetrex.Connectors` - API functions for managing connectors
    * `Fivetrex.Models.Group` - Parent group for connectors
  """

  @typedoc """
  The sync state string from the connector's status.

  Common values: `"scheduled"`, `"syncing"`, `"paused"`, `"rescheduled"`
  """
  @type status :: String.t()

  @typedoc """
  A Fivetran Connector struct.

  All fields may be `nil` if not provided in the API response.
  """
  @type t :: %__MODULE__{
          id: String.t() | nil,
          group_id: String.t() | nil,
          service: String.t() | nil,
          service_version: integer() | nil,
          schema: String.t() | nil,
          paused: boolean() | nil,
          pause_after_trial: boolean() | nil,
          sync_frequency: integer() | nil,
          status: map() | nil,
          setup_state: String.t() | nil,
          created_at: String.t() | nil,
          succeeded_at: String.t() | nil,
          failed_at: String.t() | nil,
          config: map() | nil
        }

  defstruct [
    :id,
    :group_id,
    :service,
    :service_version,
    :schema,
    :paused,
    :pause_after_trial,
    :sync_frequency,
    :status,
    :setup_state,
    :created_at,
    :succeeded_at,
    :failed_at,
    :config
  ]

  @doc """
  Converts a map (from JSON response) to a Connector struct.

  This function is used internally by `Fivetrex.Connectors` functions to parse
  API responses into typed structs.

  ## Parameters

    * `map` - A map with string keys from a decoded JSON response

  ## Returns

  A `%Fivetrex.Models.Connector{}` struct with fields populated from the map.

  ## Examples

      iex> map = %{"id" => "conn_123", "service" => "postgres", "paused" => false}
      iex> connector = Fivetrex.Models.Connector.from_map(map)
      iex> connector.service
      "postgres"

  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      group_id: map["group_id"],
      service: map["service"],
      service_version: map["service_version"],
      schema: map["schema"],
      paused: map["paused"],
      pause_after_trial: map["pause_after_trial"],
      sync_frequency: map["sync_frequency"],
      status: map["status"],
      setup_state: map["setup_state"],
      created_at: map["created_at"],
      succeeded_at: map["succeeded_at"],
      failed_at: map["failed_at"],
      config: map["config"]
    }
  end

  @doc """
  Returns the sync state from the connector's status map.

  The sync state indicates what the connector is currently doing.

  ## Parameters

    * `connector` - A `%Fivetrex.Models.Connector{}` struct

  ## Returns

    * `String.t()` - The sync state (e.g., `"scheduled"`, `"syncing"`, `"paused"`)
    * `nil` - If the status map is missing or doesn't contain sync_state

  ## Possible Values

    * `"scheduled"` - Waiting for next scheduled sync
    * `"syncing"` - Currently syncing data
    * `"paused"` - Connector is paused
    * `"rescheduled"` - Sync was rescheduled

  ## Examples

      iex> connector = %Fivetrex.Models.Connector{status: %{"sync_state" => "syncing"}}
      iex> Fivetrex.Models.Connector.sync_state(connector)
      "syncing"

      iex> connector = %Fivetrex.Models.Connector{status: nil}
      iex> Fivetrex.Models.Connector.sync_state(connector)
      nil

  """
  @spec sync_state(t()) :: String.t() | nil
  def sync_state(%__MODULE__{status: %{"sync_state" => state}}), do: state
  def sync_state(_), do: nil

  @doc """
  Returns true if the connector is currently syncing.

  This is a convenience function that checks if the sync_state is `"syncing"`.

  ## Parameters

    * `connector` - A `%Fivetrex.Models.Connector{}` struct

  ## Returns

    * `true` - If the connector is actively syncing data
    * `false` - If the connector is not syncing (scheduled, paused, etc.)

  ## Examples

      if Connector.syncing?(connector) do
        IO.puts("Sync in progress, please wait...")
      end

      # Find all syncing connectors
      syncing_connectors = Enum.filter(connectors, &Connector.syncing?/1)

  """
  @spec syncing?(t()) :: boolean()
  def syncing?(connector), do: sync_state(connector) == "syncing"

  @doc """
  Returns true if the connector is paused.

  A paused connector will not sync until resumed via `Fivetrex.Connectors.resume/2`.

  ## Parameters

    * `connector` - A `%Fivetrex.Models.Connector{}` struct

  ## Returns

    * `true` - If the connector is paused
    * `false` - If the connector is active (not paused)

  ## Examples

      if Connector.paused?(connector) do
        IO.puts("Connector is paused, resuming...")
        Fivetrex.Connectors.resume(client, connector.id)
      end

      # Find all paused connectors
      paused_connectors = Enum.filter(connectors, &Connector.paused?/1)

  """
  @spec paused?(t()) :: boolean()
  def paused?(%__MODULE__{paused: paused}), do: paused == true
end
