defmodule Fivetrex.Integration.ConnectorCrudTest do
  @moduledoc """
  Integration tests for connector CRUD operations using the Webhooks connector.

  The Webhooks connector is ideal for testing because:
  - No external account/credentials required
  - Uses Fivetran's managed storage (bucket_service: "Fivetran")
  - Can be fully managed via API
  - Supports all standard connector operations

  These tests create real connectors in your Fivetran account and clean up
  after themselves.
  """

  use ExUnit.Case

  @moduletag :integration

  import Fivetrex.TestHelpers

  alias Fivetrex.Models.Connector

  # Unique suffix for test resources to avoid conflicts
  defp unique_suffix, do: System.unique_integer([:positive])

  describe "connector CRUD lifecycle with webhooks" do
    setup do
      client = integration_client()

      # Create a dedicated group for this test
      group_name = "fivetrex_webhook_test_#{unique_suffix()}"
      {:ok, group} = Fivetrex.Groups.create(client, %{name: group_name})

      on_exit(fn ->
        # Cleanup: delete the test group (this also deletes connectors in it)
        Fivetrex.Groups.delete(client, group.id)
      end)

      {:ok, client: client, group_id: group.id}
    end

    test "creates a webhooks connector", %{client: client, group_id: group_id} do
      schema_name = "webhook_test_#{unique_suffix()}"

      connector_params = %{
        group_id: group_id,
        service: "webhooks",
        paused: true,
        config: %{
          schema: schema_name,
          table: "events",
          bucket_service: "Fivetran",
          auth_method: "NONE",
          sync_format: "Unpacked"
        }
      }

      assert {:ok, connector} = Fivetrex.Connectors.create(client, connector_params)
      assert %Connector{} = connector
      assert connector.id != nil
      assert connector.group_id == group_id
      assert connector.service == "webhooks"
      assert connector.paused == true
    end

    test "full CRUD lifecycle: create, read, update, delete", %{
      client: client,
      group_id: group_id
    } do
      schema_name = "webhook_crud_#{unique_suffix()}"

      # CREATE
      connector_params = %{
        group_id: group_id,
        service: "webhooks",
        paused: true,
        sync_frequency: 60,
        config: %{
          schema: schema_name,
          table: "events",
          bucket_service: "Fivetran",
          auth_method: "NONE",
          sync_format: "Unpacked"
        }
      }

      {:ok, created} = Fivetrex.Connectors.create(client, connector_params)
      assert %Connector{} = created
      assert created.service == "webhooks"
      connector_id = created.id

      # READ
      {:ok, fetched} = Fivetrex.Connectors.get(client, connector_id)
      assert fetched.id == connector_id
      assert fetched.group_id == group_id
      assert fetched.service == "webhooks"

      # UPDATE - change sync frequency
      {:ok, updated} = Fivetrex.Connectors.update(client, connector_id, %{sync_frequency: 120})
      assert updated.id == connector_id
      assert updated.sync_frequency == 120

      # DELETE
      assert :ok = Fivetrex.Connectors.delete(client, connector_id)

      # Verify deletion
      assert {:error, %Fivetrex.Error{type: :not_found}} =
               Fivetrex.Connectors.get(client, connector_id)
    end

    test "pause and resume connector", %{client: client, group_id: group_id} do
      schema_name = "webhook_pause_#{unique_suffix()}"

      # Create connector in running state
      connector_params = %{
        group_id: group_id,
        service: "webhooks",
        paused: false,
        config: %{
          schema: schema_name,
          table: "events",
          bucket_service: "Fivetran",
          auth_method: "NONE",
          sync_format: "Unpacked"
        }
      }

      {:ok, connector} = Fivetrex.Connectors.create(client, connector_params)
      connector_id = connector.id

      # Pause
      {:ok, paused} = Fivetrex.Connectors.pause(client, connector_id)
      assert Connector.paused?(paused) == true

      # Resume
      {:ok, resumed} = Fivetrex.Connectors.resume(client, connector_id)
      assert Connector.paused?(resumed) == false

      # Cleanup
      Fivetrex.Connectors.delete(client, connector_id)
    end

    test "connector helper functions work correctly", %{client: client, group_id: group_id} do
      schema_name = "webhook_helpers_#{unique_suffix()}"

      connector_params = %{
        group_id: group_id,
        service: "webhooks",
        paused: true,
        config: %{
          schema: schema_name,
          table: "events",
          bucket_service: "Fivetran",
          auth_method: "NONE",
          sync_format: "Unpacked"
        }
      }

      {:ok, connector} = Fivetrex.Connectors.create(client, connector_params)

      # Test helper functions
      assert is_boolean(Connector.paused?(connector))
      assert is_boolean(Connector.syncing?(connector))
      sync_state = Connector.sync_state(connector)
      assert is_binary(sync_state) or is_nil(sync_state)

      # Cleanup
      Fivetrex.Connectors.delete(client, connector.id)
    end

    test "list connectors includes created webhook connector", %{
      client: client,
      group_id: group_id
    } do
      schema_name = "webhook_list_#{unique_suffix()}"

      connector_params = %{
        group_id: group_id,
        service: "webhooks",
        paused: true,
        config: %{
          schema: schema_name,
          table: "events",
          bucket_service: "Fivetran",
          auth_method: "NONE",
          sync_format: "Unpacked"
        }
      }

      {:ok, created} = Fivetrex.Connectors.create(client, connector_params)

      # List connectors in group
      {:ok, %{items: connectors}} = Fivetrex.Connectors.list(client, group_id)
      assert connectors != []

      connector_ids = Enum.map(connectors, & &1.id)
      assert created.id in connector_ids

      # Stream connectors
      streamed =
        client
        |> Fivetrex.Connectors.stream(group_id)
        |> Enum.to_list()

      streamed_ids = Enum.map(streamed, & &1.id)
      assert created.id in streamed_ids

      # Cleanup
      Fivetrex.Connectors.delete(client, created.id)
    end

    test "trigger sync on webhook connector", %{client: client, group_id: group_id} do
      schema_name = "webhook_sync_#{unique_suffix()}"

      connector_params = %{
        group_id: group_id,
        service: "webhooks",
        paused: false,
        config: %{
          schema: schema_name,
          table: "events",
          bucket_service: "Fivetran",
          auth_method: "NONE",
          sync_format: "Unpacked"
        }
      }

      {:ok, connector} = Fivetrex.Connectors.create(client, connector_params)
      connector_id = connector.id

      # Trigger sync - may succeed or fail depending on connector state
      case Fivetrex.Connectors.sync(client, connector_id) do
        {:ok, result} ->
          assert is_map(result)
          assert Map.has_key?(result, :success)
          IO.puts("\n    [INFO] Sync triggered: success=#{result.success}")

        {:error, %Fivetrex.Error{} = error} ->
          # Sync might fail if connector isn't fully set up yet
          IO.puts("\n    [INFO] Sync returned error: #{error.message}")
      end

      # Cleanup
      Fivetrex.Connectors.delete(client, connector_id)
    end
  end

  describe "error handling" do
    setup do
      {:ok, client: integration_client()}
    end

    test "create connector with invalid group returns error", %{client: client} do
      connector_params = %{
        group_id: "nonexistent_group_#{unique_suffix()}",
        service: "webhooks",
        config: %{
          schema: "test",
          table: "events",
          bucket_service: "Fivetran"
        }
      }

      assert {:error, %Fivetrex.Error{}} = Fivetrex.Connectors.create(client, connector_params)
    end

    test "get nonexistent connector returns not_found", %{client: client} do
      assert {:error, %Fivetrex.Error{type: :not_found}} =
               Fivetrex.Connectors.get(client, "nonexistent_connector_#{unique_suffix()}")
    end

    test "delete nonexistent connector returns not_found", %{client: client} do
      assert {:error, %Fivetrex.Error{type: :not_found}} =
               Fivetrex.Connectors.delete(client, "nonexistent_connector_#{unique_suffix()}")
    end
  end
end
