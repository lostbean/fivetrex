defmodule Fivetrex.Models.LogEntryTest do
  use ExUnit.Case, async: true

  alias Fivetrex.Models.LogEntry

  describe "from_row/1" do
    test "creates a LogEntry struct from a complete map" do
      row = %{
        "id" => "log_123",
        "time_stamp" => "2024-01-15T10:30:00Z",
        "connector_id" => "conn_456",
        "event" => "sync_start",
        "message_event" => "info",
        "message_data" => ~s({"rows_synced": 1000})
      }

      entry = LogEntry.from_row(row)

      assert %LogEntry{} = entry
      assert entry.id == "log_123"
      assert entry.connector_id == "conn_456"
      assert entry.event == "sync_start"
      assert entry.message_event == "info"
      assert entry.message_data == ~s({"rows_synced": 1000})
      assert %DateTime{} = entry.time_stamp
      assert DateTime.to_iso8601(entry.time_stamp) == "2024-01-15T10:30:00Z"
    end

    test "creates a LogEntry struct from an empty map" do
      entry = LogEntry.from_row(%{})

      assert %LogEntry{} = entry
      assert entry.id == nil
      assert entry.time_stamp == nil
      assert entry.connector_id == nil
      assert entry.event == nil
      assert entry.message_event == nil
      assert entry.message_data == nil
    end

    test "creates a LogEntry struct with partial fields" do
      row = %{"id" => "log_partial", "event" => "sync_end"}

      entry = LogEntry.from_row(row)

      assert entry.id == "log_partial"
      assert entry.event == "sync_end"
      assert entry.connector_id == nil
      assert entry.time_stamp == nil
    end

    test "ignores extra fields in the map" do
      row = %{
        "id" => "log_123",
        "event" => "sync_start",
        "extra_field" => "ignored",
        "another_field" => 123
      }

      entry = LogEntry.from_row(row)

      assert entry.id == "log_123"
      assert entry.event == "sync_start"
      refute Map.has_key?(Map.from_struct(entry), :extra_field)
    end

    test "handles nil values in map" do
      row = %{
        "id" => nil,
        "time_stamp" => nil,
        "connector_id" => nil,
        "event" => nil,
        "message_event" => nil,
        "message_data" => nil
      }

      entry = LogEntry.from_row(row)

      assert entry.id == nil
      assert entry.time_stamp == nil
      assert entry.connector_id == nil
      assert entry.event == nil
    end
  end

  describe "from_row/1 DateTime parsing" do
    test "parses ISO 8601 string into DateTime" do
      row = %{"time_stamp" => "2024-01-15T10:30:00Z"}

      entry = LogEntry.from_row(row)

      assert %DateTime{} = entry.time_stamp
      assert entry.time_stamp.year == 2024
      assert entry.time_stamp.month == 1
      assert entry.time_stamp.day == 15
      assert entry.time_stamp.hour == 10
      assert entry.time_stamp.minute == 30
      assert entry.time_stamp.second == 0
    end

    test "parses ISO 8601 string with timezone offset" do
      row = %{"time_stamp" => "2024-01-15T10:30:00+05:00"}

      entry = LogEntry.from_row(row)

      assert %DateTime{} = entry.time_stamp
      # DateTime.from_iso8601 converts to UTC
      assert entry.time_stamp.hour == 5
      assert entry.time_stamp.minute == 30
    end

    test "keeps DateTime if already a DateTime" do
      datetime = ~U[2024-01-15 10:30:00Z]
      row = %{"time_stamp" => datetime}

      entry = LogEntry.from_row(row)

      assert entry.time_stamp == datetime
    end

    test "returns nil for invalid datetime string" do
      row = %{"time_stamp" => "not-a-datetime"}

      entry = LogEntry.from_row(row)

      assert entry.time_stamp == nil
    end

    test "returns nil for empty string" do
      row = %{"time_stamp" => ""}

      entry = LogEntry.from_row(row)

      assert entry.time_stamp == nil
    end

    test "returns nil for non-string, non-DateTime values" do
      row = %{"time_stamp" => 12_345}

      entry = LogEntry.from_row(row)

      assert entry.time_stamp == nil
    end

    test "returns nil for nil value" do
      row = %{"time_stamp" => nil}

      entry = LogEntry.from_row(row)

      assert entry.time_stamp == nil
    end
  end

  describe "from_rows/1" do
    test "parses a list of maps into LogEntry structs" do
      rows = [
        %{"id" => "log_1", "event" => "sync_start", "connector_id" => "conn_1"},
        %{"id" => "log_2", "event" => "sync_end", "connector_id" => "conn_1"},
        %{"id" => "log_3", "event" => "create_table", "connector_id" => "conn_2"}
      ]

      entries = LogEntry.from_rows(rows)

      assert length(entries) == 3
      assert Enum.all?(entries, &match?(%LogEntry{}, &1))
      assert Enum.at(entries, 0).id == "log_1"
      assert Enum.at(entries, 1).id == "log_2"
      assert Enum.at(entries, 2).id == "log_3"
    end

    test "returns empty list for empty input" do
      entries = LogEntry.from_rows([])

      assert entries == []
    end

    test "handles mixed complete and partial rows" do
      rows = [
        %{
          "id" => "log_1",
          "time_stamp" => "2024-01-15T10:30:00Z",
          "event" => "sync_start"
        },
        %{"id" => "log_2"},
        %{}
      ]

      entries = LogEntry.from_rows(rows)

      assert length(entries) == 3
      assert Enum.at(entries, 0).event == "sync_start"
      assert Enum.at(entries, 1).id == "log_2"
      assert Enum.at(entries, 2).id == nil
    end
  end

  describe "sync_start?/1" do
    test "returns true for sync_start event" do
      entry = %LogEntry{event: "sync_start"}

      assert LogEntry.sync_start?(entry) == true
    end

    test "returns false for sync_end event" do
      entry = %LogEntry{event: "sync_end"}

      assert LogEntry.sync_start?(entry) == false
    end

    test "returns false for other events" do
      events = ["create_table", "alter_table", "status", "info"]

      for event <- events do
        entry = %LogEntry{event: event}
        assert LogEntry.sync_start?(entry) == false
      end
    end

    test "returns false for nil event" do
      entry = %LogEntry{event: nil}

      assert LogEntry.sync_start?(entry) == false
    end
  end

  describe "sync_end?/1" do
    test "returns true for sync_end event" do
      entry = %LogEntry{event: "sync_end"}

      assert LogEntry.sync_end?(entry) == true
    end

    test "returns false for sync_start event" do
      entry = %LogEntry{event: "sync_start"}

      assert LogEntry.sync_end?(entry) == false
    end

    test "returns false for other events" do
      events = ["create_table", "alter_table", "status", "info"]

      for event <- events do
        entry = %LogEntry{event: event}
        assert LogEntry.sync_end?(entry) == false
      end
    end

    test "returns false for nil event" do
      entry = %LogEntry{event: nil}

      assert LogEntry.sync_end?(entry) == false
    end
  end

  describe "schema_change?/1" do
    test "returns true for create_table event" do
      entry = %LogEntry{event: "create_table"}

      assert LogEntry.schema_change?(entry) == true
    end

    test "returns true for alter_table event" do
      entry = %LogEntry{event: "alter_table"}

      assert LogEntry.schema_change?(entry) == true
    end

    test "returns true for drop_table event" do
      entry = %LogEntry{event: "drop_table"}

      assert LogEntry.schema_change?(entry) == true
    end

    test "returns true for create_schema event" do
      entry = %LogEntry{event: "create_schema"}

      assert LogEntry.schema_change?(entry) == true
    end

    test "returns false for sync_start event" do
      entry = %LogEntry{event: "sync_start"}

      assert LogEntry.schema_change?(entry) == false
    end

    test "returns false for sync_end event" do
      entry = %LogEntry{event: "sync_end"}

      assert LogEntry.schema_change?(entry) == false
    end

    test "returns false for other events" do
      events = ["status", "info", "warning", "error"]

      for event <- events do
        entry = %LogEntry{event: event}
        assert LogEntry.schema_change?(entry) == false
      end
    end

    test "returns false for nil event" do
      entry = %LogEntry{event: nil}

      assert LogEntry.schema_change?(entry) == false
    end
  end
end
