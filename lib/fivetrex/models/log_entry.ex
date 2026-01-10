defmodule Fivetrex.Models.LogEntry do
  @moduledoc """
  Represents a row from the Fivetran Platform LOG table.

  This struct is useful for parsing warehouse query results when querying the
  Fivetran LOG table. The LOG table contains detailed records of connector
  activity including sync events, schema changes, and error messages.

  ## Fields

    * `:id` - Unique identifier for the log entry
    * `:time_stamp` - When the event occurred (parsed as DateTime)
    * `:connector_id` - The connector that generated this log entry
    * `:event` - Event type (e.g., `"sync_start"`, `"sync_end"`, `"create_table"`)
    * `:message_event` - Additional event classification
    * `:message_data` - Event-specific data, often JSON (kept as string)

  ## Common Event Types

    * `"sync_start"` - Connector sync started
    * `"sync_end"` - Connector sync completed
    * `"create_table"` - New table created in destination
    * `"alter_table"` - Table schema modified
    * `"drop_table"` - Table removed from destination
    * `"create_schema"` - New schema created in destination

  ## Helper Functions

  This module provides convenience functions to check event types:

      if LogEntry.sync_start?(entry) do
        IO.puts("Sync started at: \#{entry.time_stamp}")
      end

      if LogEntry.schema_change?(entry) do
        IO.puts("Schema changed: \#{entry.event}")
      end

  ## Examples

  Parsing warehouse query results:

      rows = MyWarehouse.query("SELECT * FROM fivetran_log.log LIMIT 100")
      entries = Fivetrex.Models.LogEntry.from_rows(rows)

      # Find sync events
      sync_events = Enum.filter(entries, fn entry ->
        LogEntry.sync_start?(entry) or LogEntry.sync_end?(entry)
      end)

  ## See Also

    * `Fivetrex.SyncLogs` - Query examples and utilities for working with log data
  """

  @typedoc """
  A Fivetran LOG table row struct.

  All fields may be `nil` if not provided in the query results.
  """
  @type t :: %__MODULE__{
          id: String.t() | nil,
          time_stamp: DateTime.t() | nil,
          connector_id: String.t() | nil,
          event: String.t() | nil,
          message_event: String.t() | nil,
          message_data: String.t() | nil
        }

  defstruct [
    :id,
    :time_stamp,
    :connector_id,
    :event,
    :message_event,
    :message_data
  ]

  @schema_change_events ["create_table", "alter_table", "drop_table", "create_schema"]

  @doc """
  Parses a map (with string keys from warehouse query) into a LogEntry struct.

  This function handles DateTime parsing for the `time_stamp` field. If the value
  is already a DateTime, it is kept as-is. If it's a string, it attempts to parse
  using `DateTime.from_iso8601/1`. If parsing fails, the field is set to `nil`.

  ## Parameters

    * `row` - A map with string keys from a warehouse query result

  ## Returns

  A `%Fivetrex.Models.LogEntry{}` struct with fields populated from the map.

  ## Examples

      iex> row = %{
      ...>   "id" => "log_123",
      ...>   "time_stamp" => "2024-01-15T10:30:00Z",
      ...>   "connector_id" => "conn_456",
      ...>   "event" => "sync_start"
      ...> }
      iex> entry = Fivetrex.Models.LogEntry.from_row(row)
      iex> entry.event
      "sync_start"

  """
  @spec from_row(map()) :: t()
  def from_row(row) when is_map(row) do
    %__MODULE__{
      id: row["id"],
      time_stamp: parse_datetime(row["time_stamp"]),
      connector_id: row["connector_id"],
      event: row["event"],
      message_event: row["message_event"],
      message_data: row["message_data"]
    }
  end

  @doc """
  Parses a list of maps into a list of LogEntry structs.

  ## Parameters

    * `rows` - A list of maps with string keys from warehouse query results

  ## Returns

  A list of `%Fivetrex.Models.LogEntry{}` structs.

  ## Examples

      iex> rows = [
      ...>   %{"id" => "log_1", "event" => "sync_start"},
      ...>   %{"id" => "log_2", "event" => "sync_end"}
      ...> ]
      iex> entries = Fivetrex.Models.LogEntry.from_rows(rows)
      iex> length(entries)
      2

  """
  @spec from_rows([map()]) :: [t()]
  def from_rows(rows) when is_list(rows) do
    Enum.map(rows, &from_row/1)
  end

  @doc """
  Returns true if this is a sync_start event.

  ## Parameters

    * `entry` - A `%Fivetrex.Models.LogEntry{}` struct

  ## Returns

    * `true` - If the event type is `"sync_start"`
    * `false` - Otherwise

  ## Examples

      iex> entry = %Fivetrex.Models.LogEntry{event: "sync_start"}
      iex> Fivetrex.Models.LogEntry.sync_start?(entry)
      true

      iex> entry = %Fivetrex.Models.LogEntry{event: "sync_end"}
      iex> Fivetrex.Models.LogEntry.sync_start?(entry)
      false

  """
  @spec sync_start?(t()) :: boolean()
  def sync_start?(%__MODULE__{event: event}), do: event == "sync_start"

  @doc """
  Returns true if this is a sync_end event.

  ## Parameters

    * `entry` - A `%Fivetrex.Models.LogEntry{}` struct

  ## Returns

    * `true` - If the event type is `"sync_end"`
    * `false` - Otherwise

  ## Examples

      iex> entry = %Fivetrex.Models.LogEntry{event: "sync_end"}
      iex> Fivetrex.Models.LogEntry.sync_end?(entry)
      true

      iex> entry = %Fivetrex.Models.LogEntry{event: "sync_start"}
      iex> Fivetrex.Models.LogEntry.sync_end?(entry)
      false

  """
  @spec sync_end?(t()) :: boolean()
  def sync_end?(%__MODULE__{event: event}), do: event == "sync_end"

  @doc """
  Returns true if this is a schema change event.

  Schema change events indicate modifications to the destination schema,
  including table creation, alteration, and deletion.

  The following events are considered schema changes:

    * `"create_table"` - New table created
    * `"alter_table"` - Table schema modified
    * `"drop_table"` - Table removed
    * `"create_schema"` - New schema created

  ## Parameters

    * `entry` - A `%Fivetrex.Models.LogEntry{}` struct

  ## Returns

    * `true` - If the event is a schema change event
    * `false` - Otherwise

  ## Examples

      iex> entry = %Fivetrex.Models.LogEntry{event: "create_table"}
      iex> Fivetrex.Models.LogEntry.schema_change?(entry)
      true

      iex> entry = %Fivetrex.Models.LogEntry{event: "alter_table"}
      iex> Fivetrex.Models.LogEntry.schema_change?(entry)
      true

      iex> entry = %Fivetrex.Models.LogEntry{event: "sync_start"}
      iex> Fivetrex.Models.LogEntry.schema_change?(entry)
      false

  """
  @spec schema_change?(t()) :: boolean()
  def schema_change?(%__MODULE__{event: event}), do: event in @schema_change_events

  # Private helper to parse datetime values
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp parse_datetime(_), do: nil
end
