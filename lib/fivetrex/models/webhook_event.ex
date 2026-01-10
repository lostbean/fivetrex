defmodule Fivetrex.Models.WebhookEvent do
  @moduledoc """
  Represents an incoming Fivetran webhook event payload.

  When Fivetran sends a webhook notification to your endpoint, the payload
  contains information about what triggered the event. Use this struct to
  parse and work with webhook payloads in a typed manner.

  ## Fields

    * `:event` - Event type (e.g., `"sync_start"`, `"sync_end"`)
    * `:created` - DateTime when the event was created (parsed from ISO 8601)
    * `:connector_id` - The connector that triggered the event
    * `:connector_type` - Connector service type (e.g., `"postgres"`, `"salesforce"`)
    * `:group_id` - Group containing the connector
    * `:data` - Event-specific data (varies by event type)

  ## Event Types

    * `"sync_start"` - Connector sync started
    * `"sync_end"` - Connector sync completed (check `data` for success/failure)
    * `"status"` - Connector status changed
    * `"dbt_run_start"` - dbt transformation started
    * `"dbt_run_succeeded"` - dbt transformation succeeded
    * `"dbt_run_failed"` - dbt transformation failed

  ## Data Field

  The `:data` field contains event-specific information. For `sync_end` events,
  it typically includes:

  ```elixir
  %{
    "status" => "SUCCESSFUL",  # or "FAILURE_WITH_TASK"
    "reason" => nil            # Error message on failure
  }
  ```

  ## Helper Functions

  This module provides convenience functions to check event types:

      if WebhookEvent.sync_end?(event) do
        handle_sync_completion(event)
      end

  ## Examples

  Parsing a webhook payload in a Phoenix controller:

      def receive(conn, params) do
        event = Fivetrex.Models.WebhookEvent.from_map(params)

        case event.event do
          "sync_end" ->
            IO.puts("Sync finished for connector: \#{event.connector_id}")
          "sync_start" ->
            IO.puts("Sync started for connector: \#{event.connector_id}")
          _ ->
            IO.puts("Received event: \#{event.event}")
        end

        json(conn, %{status: "ok"})
      end

  Filtering for specific events:

      if WebhookEvent.sync_end?(event) do
        process_completed_sync(event.connector_id, event.data)
      end

  ## See Also

    * `Fivetrex.Webhooks` - API functions for managing webhooks
    * `Fivetrex.WebhookSignature` - Signature verification for incoming webhooks
    * `Fivetrex.WebhookPlug` - Plug for Phoenix/Bandit webhook handling
  """

  @typedoc """
  A Fivetran Webhook Event struct.

  All fields may be `nil` if not provided in the webhook payload.
  """
  @type t :: %__MODULE__{
          event: String.t() | nil,
          created: DateTime.t() | nil,
          connector_id: String.t() | nil,
          connector_type: String.t() | nil,
          group_id: String.t() | nil,
          data: map() | nil
        }

  defstruct [
    :event,
    :created,
    :connector_id,
    :connector_type,
    :group_id,
    :data
  ]

  @doc """
  Converts a map (from webhook JSON payload) to a WebhookEvent struct.

  This function parses incoming webhook payloads into typed structs for
  easier processing.

  ## Parameters

    * `map` - A map with string keys from a decoded JSON webhook payload

  ## Returns

  A `%Fivetrex.Models.WebhookEvent{}` struct with fields populated from the map.

  ## Examples

      iex> map = %{"event" => "sync_end", "connector_id" => "conn_123"}
      iex> event = Fivetrex.Models.WebhookEvent.from_map(map)
      iex> event.event
      "sync_end"

  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      event: map["event"],
      created: parse_datetime(map["created"]),
      connector_id: map["connector_id"],
      connector_type: map["connector_type"],
      group_id: map["group_id"],
      data: map["data"]
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

  @doc """
  Returns true if this is a sync_start event.

  ## Parameters

    * `event` - A `%Fivetrex.Models.WebhookEvent{}` struct

  ## Returns

    * `true` - If the event type is `"sync_start"`
    * `false` - Otherwise

  ## Examples

      iex> event = %Fivetrex.Models.WebhookEvent{event: "sync_start"}
      iex> Fivetrex.Models.WebhookEvent.sync_start?(event)
      true

  """
  @spec sync_start?(t()) :: boolean()
  def sync_start?(%__MODULE__{event: event}), do: event == "sync_start"

  @doc """
  Returns true if this is a sync_end event.

  Sync end events indicate a connector has finished syncing. Check the
  `data` field for success/failure status.

  ## Parameters

    * `event` - A `%Fivetrex.Models.WebhookEvent{}` struct

  ## Returns

    * `true` - If the event type is `"sync_end"`
    * `false` - Otherwise

  ## Examples

      iex> event = %Fivetrex.Models.WebhookEvent{event: "sync_end"}
      iex> Fivetrex.Models.WebhookEvent.sync_end?(event)
      true

      # Check if sync was successful
      if WebhookEvent.sync_end?(event) do
        case event.data do
          %{"status" => "SUCCESSFUL"} -> handle_success(event)
          %{"status" => "FAILURE_WITH_TASK"} -> handle_failure(event)
        end
      end

  """
  @spec sync_end?(t()) :: boolean()
  def sync_end?(%__MODULE__{event: event}), do: event == "sync_end"
end
