defmodule Fivetrex.Integration.ConnectorsTest do
  use ExUnit.Case

  @moduletag :integration

  import Fivetrex.TestHelpers

  alias Fivetrex.Models.Connector

  setup do
    client = integration_client()

    # Get the first group to use for connector tests
    {:ok, %{items: [group | _]}} = Fivetrex.Groups.list(client)

    {:ok, client: client, group_id: group.id}
  end

  describe "read operations" do
    test "lists connectors in a group", %{client: client, group_id: group_id} do
      assert {:ok, %{items: connectors}} = Fivetrex.Connectors.list(client, group_id)
      assert is_list(connectors)
    end

    test "streams connectors in a group", %{client: client, group_id: group_id} do
      connectors =
        client
        |> Fivetrex.Connectors.stream(group_id)
        |> Enum.take(5)

      assert is_list(connectors)
    end

    test "gets a single connector", %{client: client, group_id: group_id} do
      case Fivetrex.Connectors.list(client, group_id) do
        {:ok, %{items: [connector | _]}} ->
          assert {:ok, fetched} = Fivetrex.Connectors.get(client, connector.id)
          assert %Connector{} = fetched
          assert fetched.id == connector.id
          assert fetched.service != nil

        {:ok, %{items: []}} ->
          # No connectors in this group, skip test
          assert true
      end
    end
  end

  describe "sync operations" do
    setup %{client: client, group_id: group_id} do
      # Find a connector to test with
      case Fivetrex.Connectors.list(client, group_id) do
        {:ok, %{items: [connector | _]}} ->
          {:ok, connector_id: connector.id}

        {:ok, %{items: []}} ->
          {:ok, connector_id: nil}
      end
    end

    test "gets connector state", %{client: client, connector_id: connector_id} do
      if connector_id do
        # Note: get_state endpoint may not be available for all connector types
        # or may require specific permissions
        case Fivetrex.Connectors.get_state(client, connector_id) do
          {:ok, state} ->
            assert is_map(state)

          {:error, %Fivetrex.Error{status: 405}} ->
            # Method not allowed - endpoint may not be available
            assert true

          {:error, %Fivetrex.Error{type: :not_found}} ->
            # State not available for this connector
            assert true
        end
      else
        # No connectors to test with
        assert true
      end
    end

    test "pauses and resumes a connector", %{client: client, connector_id: connector_id} do
      if connector_id do
        # Get initial state
        {:ok, initial} = Fivetrex.Connectors.get(client, connector_id)

        try do
          # Pause the connector
          assert {:ok, paused} = Fivetrex.Connectors.pause(client, connector_id)
          assert %Connector{} = paused
          assert Connector.paused?(paused) == true

          # Resume the connector
          assert {:ok, resumed} = Fivetrex.Connectors.resume(client, connector_id)
          assert %Connector{} = resumed
          assert Connector.paused?(resumed) == false
        after
          # Restore original state
          if initial.paused do
            Fivetrex.Connectors.pause(client, connector_id)
          else
            Fivetrex.Connectors.resume(client, connector_id)
          end
        end
      else
        # No connectors to test with
        assert true
      end
    end

    test "triggers a sync", %{client: client, connector_id: connector_id} do
      if connector_id do
        # Trigger sync - returns immediately, sync runs async
        case Fivetrex.Connectors.sync(client, connector_id) do
          {:ok, result} ->
            # Verify normalized response shape
            assert is_map(result)
            assert Map.has_key?(result, :success)
            assert result.success == true

          {:error, %Fivetrex.Error{} = error} ->
            # Sync might fail if connector is paused, not connected, etc.
            # This is acceptable for this test
            assert error.type in [:unknown, :server_error]
        end
      else
        # No connectors to test with
        assert true
      end
    end

    test "checks sync state with helper functions", %{client: client, connector_id: connector_id} do
      if connector_id do
        {:ok, connector} = Fivetrex.Connectors.get(client, connector_id)

        # Test helper functions work on real connector data
        sync_state = Connector.sync_state(connector)
        syncing = Connector.syncing?(connector)
        paused = Connector.paused?(connector)

        # sync_state should be a string or nil
        assert is_binary(sync_state) or is_nil(sync_state)
        # syncing? and paused? should be boolean
        assert is_boolean(syncing)
        assert is_boolean(paused)
      else
        assert true
      end
    end
  end
end
