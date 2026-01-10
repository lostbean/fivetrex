defmodule Fivetrex.Models.SyncStatus do
  @moduledoc """
  Represents the sync status summary for a Fivetran Connector.

  This struct provides a structured view of a connector's current sync state,
  including timing information and sync progress. It's returned by
  `Fivetrex.Connectors.get_sync_status/2`.

  ## Fields

    * `:sync_state` - Current sync state of the connector
    * `:succeeded_at` - DateTime of the last successful sync (parsed from ISO 8601)
    * `:failed_at` - DateTime of the last failed sync (parsed from ISO 8601)
    * `:is_historical_sync` - Whether a historical sync is currently in progress
    * `:update_state` - The update status of the connector

  ## Sync State Values

  The `:sync_state` field can be one of:

    * `"syncing"` - Connector is actively syncing data
    * `"scheduled"` - Connector is waiting for its next scheduled sync
    * `"paused"` - Connector has been manually paused
    * `"rescheduled"` - Sync was rescheduled (e.g., due to rate limiting)

  ## Update State Values

  The `:update_state` field indicates the connector's update status:

    * `"on_schedule"` - Connector is syncing on its normal schedule
    * `"delayed"` - Connector sync is delayed

  ## Helper Functions

  This module provides helper functions to check sync state:

      if SyncStatus.syncing?(status) do
        IO.puts("Sync in progress...")
      end

      if SyncStatus.paused?(status) do
        IO.puts("Connector is paused")
      end

  ## Examples

      {:ok, status} = Fivetrex.Connectors.get_sync_status(client, "connector_id")
      IO.puts("Current state: \#{status.sync_state}")
      IO.puts("Last success: \#{status.succeeded_at}")

      if SyncStatus.syncing?(status) do
        IO.puts("Sync in progress...")
      end

  ## See Also

    * `Fivetrex.Connectors.get_sync_status/2` - Retrieves sync status for a connector
    * `Fivetrex.Models.Connector` - The full connector struct
  """

  alias Fivetrex.Models.Connector

  @typedoc """
  A sync status summary struct.

  All fields may be `nil` if not provided in the API response.
  """
  @type t :: %__MODULE__{
          sync_state: String.t() | nil,
          succeeded_at: DateTime.t() | nil,
          failed_at: DateTime.t() | nil,
          is_historical_sync: boolean() | nil,
          update_state: String.t() | nil
        }

  defstruct [
    :sync_state,
    :succeeded_at,
    :failed_at,
    :is_historical_sync,
    :update_state
  ]

  @doc """
  Returns true if the sync state is "syncing".

  ## Parameters

    * `status` - A `%Fivetrex.Models.SyncStatus{}` struct

  ## Returns

    * `true` - If the connector is actively syncing data
    * `false` - If the connector is not syncing

  ## Examples

      iex> status = %Fivetrex.Models.SyncStatus{sync_state: "syncing"}
      iex> Fivetrex.Models.SyncStatus.syncing?(status)
      true

      iex> status = %Fivetrex.Models.SyncStatus{sync_state: "scheduled"}
      iex> Fivetrex.Models.SyncStatus.syncing?(status)
      false

  """
  @spec syncing?(t()) :: boolean()
  def syncing?(%__MODULE__{sync_state: state}), do: state == "syncing"

  @doc """
  Returns true if the sync state is "paused".

  ## Parameters

    * `status` - A `%Fivetrex.Models.SyncStatus{}` struct

  ## Returns

    * `true` - If the connector is paused
    * `false` - If the connector is not paused

  ## Examples

      iex> status = %Fivetrex.Models.SyncStatus{sync_state: "paused"}
      iex> Fivetrex.Models.SyncStatus.paused?(status)
      true

      iex> status = %Fivetrex.Models.SyncStatus{sync_state: "syncing"}
      iex> Fivetrex.Models.SyncStatus.paused?(status)
      false

  """
  @spec paused?(t()) :: boolean()
  def paused?(%__MODULE__{sync_state: state}), do: state == "paused"

  @doc """
  Returns true if the sync state is "scheduled".

  ## Parameters

    * `status` - A `%Fivetrex.Models.SyncStatus{}` struct

  ## Returns

    * `true` - If the connector is scheduled for sync
    * `false` - If the connector is not in scheduled state

  ## Examples

      iex> status = %Fivetrex.Models.SyncStatus{sync_state: "scheduled"}
      iex> Fivetrex.Models.SyncStatus.scheduled?(status)
      true

      iex> status = %Fivetrex.Models.SyncStatus{sync_state: "syncing"}
      iex> Fivetrex.Models.SyncStatus.scheduled?(status)
      false

  """
  @spec scheduled?(t()) :: boolean()
  def scheduled?(%__MODULE__{sync_state: state}), do: state == "scheduled"

  @doc """
  Creates a SyncStatus struct from a Connector struct.

  Extracts the relevant sync status fields from a full Connector struct.

  ## Parameters

    * `connector` - A `%Fivetrex.Models.Connector{}` struct

  ## Returns

  A `%Fivetrex.Models.SyncStatus{}` struct with fields populated from the connector.

  ## Examples

      iex> connector = %Fivetrex.Models.Connector{
      ...>   status: %{"sync_state" => "syncing", "is_historical_sync" => false, "update_state" => "on_schedule"},
      ...>   succeeded_at: "2024-01-01T00:00:00Z",
      ...>   failed_at: nil
      ...> }
      iex> status = Fivetrex.Models.SyncStatus.from_connector(connector)
      iex> status.sync_state
      "syncing"
      iex> status.succeeded_at
      ~U[2024-01-01 00:00:00Z]

  """
  @spec from_connector(Connector.t()) :: t()
  def from_connector(%Connector{} = connector) do
    %__MODULE__{
      sync_state: Connector.sync_state(connector),
      succeeded_at: parse_datetime(connector.succeeded_at),
      failed_at: parse_datetime(connector.failed_at),
      is_historical_sync: get_in(connector.status, ["is_historical_sync"]),
      update_state: get_in(connector.status, ["update_state"])
    }
  end

  # Private helper to parse datetime values
  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_datetime(_), do: nil
end
