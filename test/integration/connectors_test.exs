defmodule Fivetrex.Integration.ConnectorsTest do
  use ExUnit.Case

  @moduletag :integration

  import Fivetrex.TestHelpers

  alias Fivetrex.Models.Connector

  @no_connector_message "[SKIPPED] No connectors in test account. Create a connector to test this functionality."

  setup do
    client = integration_client()

    # Get the first group to use for connector tests
    {:ok, %{items: [group | _]}} = Fivetrex.Groups.list(client)

    # Find first connector (if any) by checking all groups
    connector_id = find_first_connector(client)

    {:ok, client: client, group_id: group.id, connector_id: connector_id}
  end

  # Search across all groups to find any connector
  defp find_first_connector(client) do
    client
    |> Fivetrex.Groups.stream()
    |> Stream.flat_map(fn group ->
      case Fivetrex.Connectors.list(client, group.id, limit: 1) do
        {:ok, %{items: [connector | _]}} -> [connector.id]
        _ -> []
      end
    end)
    |> Enum.take(1)
    |> List.first()
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

    @tag :requires_connector
    test "gets a single connector", %{client: client, connector_id: connector_id} do
      if is_nil(connector_id) do
        IO.puts("\n    #{@no_connector_message}")
      else
        assert {:ok, fetched} = Fivetrex.Connectors.get(client, connector_id)
        assert %Connector{} = fetched
        assert fetched.id == connector_id
        assert fetched.service != nil
      end
    end
  end

  describe "sync operations" do
    @tag :requires_connector
    test "gets connector state", %{client: client, connector_id: connector_id} do
      if is_nil(connector_id) do
        IO.puts("\n    #{@no_connector_message}")
      else
        # Note: get_state endpoint may not be available for all connector types
        # or may require specific permissions
        case Fivetrex.Connectors.get_state(client, connector_id) do
          {:ok, state} ->
            assert is_map(state)

          {:error, %Fivetrex.Error{status: 405}} ->
            # Method not allowed - endpoint may not be available for this connector type
            IO.puts("\n    [INFO] get_state returned 405 - not available for this connector type")

          {:error, %Fivetrex.Error{type: :not_found}} ->
            # State not available for this connector
            IO.puts(
              "\n    [INFO] get_state returned 404 - state not available for this connector"
            )
        end
      end
    end

    @tag :requires_connector
    test "pauses and resumes a connector", %{client: client, connector_id: connector_id} do
      if is_nil(connector_id) do
        IO.puts("\n    #{@no_connector_message}")
      else
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
      end
    end

    @tag :requires_connector
    test "triggers a sync", %{client: client, connector_id: connector_id} do
      if is_nil(connector_id) do
        IO.puts("\n    #{@no_connector_message}")
      else
        # Trigger sync - returns immediately, sync runs async
        case Fivetrex.Connectors.sync(client, connector_id) do
          {:ok, result} ->
            # Verify normalized response shape
            assert is_map(result)
            assert Map.has_key?(result, :success)
            assert result.success == true

          {:error, %Fivetrex.Error{} = error} ->
            # Sync might fail if connector is paused, not connected, etc.
            IO.puts("\n    [INFO] sync failed with #{error.type}: #{error.message}")
            assert error.type in [:unknown, :server_error]
        end
      end
    end

    @tag :requires_connector
    test "checks sync state with helper functions", %{client: client, connector_id: connector_id} do
      if is_nil(connector_id) do
        IO.puts("\n    #{@no_connector_message}")
      else
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
      end
    end
  end
end
