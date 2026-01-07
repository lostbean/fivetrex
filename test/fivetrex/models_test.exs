defmodule Fivetrex.ModelsTest do
  use ExUnit.Case, async: true

  alias Fivetrex.Models.{Connector, Destination, Group}

  describe "Group.from_map/1" do
    test "creates a Group struct from a complete map" do
      map = %{
        "id" => "abc123",
        "name" => "Production",
        "created_at" => "2024-01-15T10:30:00Z"
      }

      group = Group.from_map(map)

      assert %Group{} = group
      assert group.id == "abc123"
      assert group.name == "Production"
      assert group.created_at == "2024-01-15T10:30:00Z"
    end

    test "creates a Group struct from an empty map" do
      group = Group.from_map(%{})

      assert %Group{} = group
      assert group.id == nil
      assert group.name == nil
      assert group.created_at == nil
    end

    test "creates a Group struct with partial fields" do
      map = %{"id" => "partial_id"}

      group = Group.from_map(map)

      assert group.id == "partial_id"
      assert group.name == nil
      assert group.created_at == nil
    end

    test "ignores extra fields in the map" do
      map = %{
        "id" => "abc123",
        "name" => "Test",
        "created_at" => "2024-01-15T10:30:00Z",
        "extra_field" => "ignored",
        "another_field" => 123
      }

      group = Group.from_map(map)

      assert group.id == "abc123"
      assert group.name == "Test"
      # Struct doesn't have extra_field
      refute Map.has_key?(Map.from_struct(group), :extra_field)
    end

    test "handles nil values in map" do
      map = %{
        "id" => nil,
        "name" => nil,
        "created_at" => nil
      }

      group = Group.from_map(map)

      assert group.id == nil
      assert group.name == nil
      assert group.created_at == nil
    end
  end

  describe "Connector.from_map/1" do
    test "creates a Connector struct from a complete map" do
      map = %{
        "id" => "conn_123",
        "group_id" => "group_456",
        "service" => "postgres",
        "service_version" => 1,
        "schema" => "my_schema",
        "paused" => false,
        "pause_after_trial" => true,
        "sync_frequency" => 60,
        "status" => %{"sync_state" => "scheduled"},
        "setup_state" => "connected",
        "created_at" => "2024-01-15T10:30:00Z",
        "succeeded_at" => "2024-01-16T10:30:00Z",
        "failed_at" => nil,
        "config" => %{"host" => "localhost", "port" => 5432}
      }

      connector = Connector.from_map(map)

      assert %Connector{} = connector
      assert connector.id == "conn_123"
      assert connector.group_id == "group_456"
      assert connector.service == "postgres"
      assert connector.service_version == 1
      assert connector.schema == "my_schema"
      assert connector.paused == false
      assert connector.pause_after_trial == true
      assert connector.sync_frequency == 60
      assert connector.status == %{"sync_state" => "scheduled"}
      assert connector.setup_state == "connected"
      assert connector.created_at == "2024-01-15T10:30:00Z"
      assert connector.succeeded_at == "2024-01-16T10:30:00Z"
      assert connector.failed_at == nil
      assert connector.config == %{"host" => "localhost", "port" => 5432}
    end

    test "creates a Connector struct from an empty map" do
      connector = Connector.from_map(%{})

      assert %Connector{} = connector
      assert connector.id == nil
      assert connector.group_id == nil
      assert connector.service == nil
      assert connector.status == nil
      assert connector.config == nil
    end

    test "creates a Connector struct with minimal fields" do
      map = %{"id" => "conn_123", "service" => "salesforce"}

      connector = Connector.from_map(map)

      assert connector.id == "conn_123"
      assert connector.service == "salesforce"
      assert connector.paused == nil
    end

    test "ignores extra fields in the map" do
      map = %{
        "id" => "conn_123",
        "unknown_field" => "ignored",
        "nested" => %{"also" => "ignored"}
      }

      connector = Connector.from_map(map)

      assert connector.id == "conn_123"
      refute Map.has_key?(Map.from_struct(connector), :unknown_field)
    end

    test "handles complex status map" do
      map = %{
        "id" => "conn_123",
        "status" => %{
          "sync_state" => "syncing",
          "update_state" => "on_schedule",
          "is_historical_sync" => true,
          "tasks" => [%{"code" => "task1"}],
          "warnings" => []
        }
      }

      connector = Connector.from_map(map)

      assert connector.status["sync_state"] == "syncing"
      assert connector.status["is_historical_sync"] == true
      assert length(connector.status["tasks"]) == 1
    end

    test "handles complex config map" do
      map = %{
        "id" => "conn_123",
        "config" => %{
          "host" => "db.example.com",
          "port" => 5432,
          "database" => "production",
          "user" => "fivetran",
          "ssl" => true,
          "schema_list" => ["public", "sales"]
        }
      }

      connector = Connector.from_map(map)

      assert connector.config["host"] == "db.example.com"
      assert connector.config["ssl"] == true
      assert connector.config["schema_list"] == ["public", "sales"]
    end
  end

  describe "Connector.sync_state/1" do
    test "returns sync_state from status map" do
      connector = %Connector{status: %{"sync_state" => "syncing"}}

      assert Connector.sync_state(connector) == "syncing"
    end

    test "returns nil when status is nil" do
      connector = %Connector{status: nil}

      assert Connector.sync_state(connector) == nil
    end

    test "returns nil when status doesn't contain sync_state" do
      connector = %Connector{status: %{"other_key" => "value"}}

      assert Connector.sync_state(connector) == nil
    end

    test "returns nil for empty status map" do
      connector = %Connector{status: %{}}

      assert Connector.sync_state(connector) == nil
    end

    test "returns various sync states" do
      states = ["scheduled", "syncing", "paused", "rescheduled"]

      for state <- states do
        connector = %Connector{status: %{"sync_state" => state}}
        assert Connector.sync_state(connector) == state
      end
    end
  end

  describe "Connector.syncing?/1" do
    test "returns true when sync_state is 'syncing'" do
      connector = %Connector{status: %{"sync_state" => "syncing"}}

      assert Connector.syncing?(connector) == true
    end

    test "returns false when sync_state is 'scheduled'" do
      connector = %Connector{status: %{"sync_state" => "scheduled"}}

      assert Connector.syncing?(connector) == false
    end

    test "returns false when sync_state is 'paused'" do
      connector = %Connector{status: %{"sync_state" => "paused"}}

      assert Connector.syncing?(connector) == false
    end

    test "returns false when status is nil" do
      connector = %Connector{status: nil}

      assert Connector.syncing?(connector) == false
    end

    test "returns false when status is empty" do
      connector = %Connector{status: %{}}

      assert Connector.syncing?(connector) == false
    end
  end

  describe "Connector.paused?/1" do
    test "returns true when paused is true" do
      connector = %Connector{paused: true}

      assert Connector.paused?(connector) == true
    end

    test "returns false when paused is false" do
      connector = %Connector{paused: false}

      assert Connector.paused?(connector) == false
    end

    test "returns false when paused is nil" do
      connector = %Connector{paused: nil}

      assert Connector.paused?(connector) == false
    end
  end

  describe "Destination.from_map/1" do
    test "creates a Destination struct from a complete map" do
      map = %{
        "id" => "dest_123",
        "group_id" => "group_456",
        "service" => "snowflake",
        "region" => "US",
        "time_zone_offset" => "-5",
        "setup_status" => "connected",
        "config" => %{
          "host" => "account.snowflakecomputing.com",
          "database" => "ANALYTICS",
          "port" => 443
        }
      }

      destination = Destination.from_map(map)

      assert %Destination{} = destination
      assert destination.id == "dest_123"
      assert destination.group_id == "group_456"
      assert destination.service == "snowflake"
      assert destination.region == "US"
      assert destination.time_zone_offset == "-5"
      assert destination.setup_status == "connected"
      assert destination.config["host"] == "account.snowflakecomputing.com"
    end

    test "creates a Destination struct from an empty map" do
      destination = Destination.from_map(%{})

      assert %Destination{} = destination
      assert destination.id == nil
      assert destination.group_id == nil
      assert destination.service == nil
      assert destination.region == nil
      assert destination.config == nil
    end

    test "creates a Destination struct with partial fields" do
      map = %{"id" => "dest_123", "service" => "big_query"}

      destination = Destination.from_map(map)

      assert destination.id == "dest_123"
      assert destination.service == "big_query"
      assert destination.region == nil
    end

    test "ignores extra fields in the map" do
      map = %{
        "id" => "dest_123",
        "service" => "redshift",
        "unknown" => "field",
        "nested" => %{"ignored" => true}
      }

      destination = Destination.from_map(map)

      assert destination.id == "dest_123"
      assert destination.service == "redshift"
      refute Map.has_key?(Map.from_struct(destination), :unknown)
    end

    test "handles nil values in map" do
      map = %{
        "id" => nil,
        "group_id" => nil,
        "service" => nil,
        "region" => nil,
        "time_zone_offset" => nil,
        "setup_status" => nil,
        "config" => nil
      }

      destination = Destination.from_map(map)

      assert destination.id == nil
      assert destination.config == nil
    end

    test "handles various destination services" do
      services = ["snowflake", "big_query", "redshift", "databricks", "postgres"]

      for service <- services do
        map = %{"id" => "dest_#{service}", "service" => service}
        destination = Destination.from_map(map)

        assert destination.service == service
      end
    end

    test "handles various regions" do
      regions = ["US", "EU", "APAC", "US_WEST_2", "EU_WEST_1"]

      for region <- regions do
        map = %{"id" => "dest_123", "region" => region}
        destination = Destination.from_map(map)

        assert destination.region == region
      end
    end

    test "handles complex config with nested maps" do
      map = %{
        "id" => "dest_123",
        "config" => %{
          "host" => "db.example.com",
          "port" => 5439,
          "database" => "warehouse",
          "connection_settings" => %{
            "ssl" => true,
            "timeout" => 30
          }
        }
      }

      destination = Destination.from_map(map)

      assert destination.config["connection_settings"]["ssl"] == true
      assert destination.config["connection_settings"]["timeout"] == 30
    end
  end
end
