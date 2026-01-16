defmodule Fivetrex.Models.WebhookEvent do
  @moduledoc """
  Represents an incoming Fivetran webhook event payload.

  When Fivetran sends a webhook notification to your endpoint, the payload
  contains information about what triggered the event. Use this struct to
  parse and work with webhook payloads in a typed manner.

  ## Fields

  All Fivetran webhook payloads include these standard fields:

    * `:event` - Event type (e.g., `"sync_start"`, `"sync_end"`)
    * `:created` - DateTime when the event was created (parsed from ISO 8601)
    * `:connector_id` - Unique connector identifier
    * `:connector_type` - Source connector type (e.g., `"postgres"`, `"mysql"`, `"salesforce"`)
    * `:connector_name` - Human-readable connector name
    * `:sync_id` - Identifier for the specific sync operation
    * `:group_id` - Legacy field, use `:destination_group_id` instead
    * `:destination_group_id` - Destination group associated with the connector
    * `:status` - Operation status (`"SUCCESSFUL"` or `"FAILED"`)
    * `:data` - Event-specific payload (structure varies by event type)
    * `:extra` - Map of any additional fields not explicitly handled

  The `:extra` field preserves any fields not listed above, ensuring forward
  compatibility when Fivetran adds new webhook fields.

  ## Backward Compatibility

  For older webhook payloads, `:destination_group_id` will fallback to the value
  of `:group_id` if `:destination_group_id` is not present. Both fields are
  preserved in the struct.

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
    * [Fivetran Webhooks Documentation](https://fivetran.com/docs/rest-api/getting-started/webhooks)
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
          connector_name: String.t() | nil,
          sync_id: String.t() | nil,
          group_id: String.t() | nil,
          destination_group_id: String.t() | nil,
          status: String.t() | nil,
          data: map() | nil,
          extra: map()
        }

  defstruct [
    :event,
    :created,
    :connector_id,
    :connector_type,
    :connector_name,
    :sync_id,
    :group_id,
    :destination_group_id,
    :status,
    :data,
    extra: %{}
  ]

  # Known fields that are explicitly handled
  @known_fields ~w[
    event created connector_id connector_type connector_name
    sync_id group_id destination_group_id status data
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
    extra = Map.drop(map, @known_fields)

    %__MODULE__{
      event: map["event"],
      created: parse_datetime(map["created"]),
      connector_id: map["connector_id"],
      connector_type: map["connector_type"],
      connector_name: map["connector_name"],
      sync_id: map["sync_id"],
      group_id: map["group_id"],
      destination_group_id: map["destination_group_id"] || map["group_id"],
      status: map["status"],
      data: map["data"],
      extra: extra
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

  @doc """
  Returns true if the status indicates successful completion.

  This checks the top-level `:status` field. Note that some event types
  also include status information in the `:data` field. For `sync_end`
  events specifically, both the top-level status and `data["status"]`
  typically contain status information.

  ## Parameters

    * `event` - A `%Fivetrex.Models.WebhookEvent{}` struct

  ## Returns

    * `true` - If the status is `"SUCCESSFUL"`
    * `false` - Otherwise (including when status is `nil`)

  ## Examples

      iex> event = %Fivetrex.Models.WebhookEvent{status: "SUCCESSFUL"}
      iex> Fivetrex.Models.WebhookEvent.successful?(event)
      true

      iex> event = %Fivetrex.Models.WebhookEvent{status: "FAILED"}
      iex> Fivetrex.Models.WebhookEvent.successful?(event)
      false

      # Practical usage
      if WebhookEvent.sync_end?(event) and WebhookEvent.successful?(event) do
        Logger.info("Sync completed successfully for \#{event.connector_id}")
      end

  ## See Also

    * `failed?/1` - Check if status indicates failure
    * `sync_end?/1` - Check if this is a sync completion event

  """
  @spec successful?(t()) :: boolean()
  def successful?(%__MODULE__{status: "SUCCESSFUL"}), do: true
  def successful?(_), do: false

  @doc """
  Returns true if the status indicates failure.

  This checks the top-level `:status` field. For detailed error information
  on `sync_end` events, check the `data["reason"]` field.

  ## Parameters

    * `event` - A `%Fivetrex.Models.WebhookEvent{}` struct

  ## Returns

    * `true` - If the status is `"FAILED"`
    * `false` - Otherwise (including when status is `nil`)

  ## Examples

      iex> event = %Fivetrex.Models.WebhookEvent{status: "FAILED"}
      iex> Fivetrex.Models.WebhookEvent.failed?(event)
      true

      # Handle failures with error details
      if WebhookEvent.sync_end?(event) and WebhookEvent.failed?(event) do
        reason = get_in(event.data, ["reason"]) || "Unknown error"
        Logger.error("Sync failed for \#{event.connector_id}: \#{reason}")
      end

  ## See Also

    * `successful?/1` - Check if status indicates success
    * `sync_end?/1` - Check if this is a sync completion event

  """
  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{status: "FAILED"}), do: true
  def failed?(_), do: false
end
