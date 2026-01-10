defmodule Fivetrex.Integration.ConnectorsTest do
  @moduledoc """
  Integration tests for Fivetrex.Connectors.

  Run with: `mix test --include integration`

  Some tests are marked with `@tag :slow` because they may take significant time.
  These are excluded by default. Run with `--include slow` to include them.
  """

  use ExUnit.Case

  @moduletag :integration

  import Fivetrex.TestHelpers

  alias Fivetrex.Models.Connector
  alias Fivetrex.Models.SyncStatus

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

  describe "sync status and frequency" do
    @tag :requires_connector
    test "gets sync status", %{client: client, connector_id: connector_id} do
      if is_nil(connector_id) do
        IO.puts("\n    #{@no_connector_message}")
      else
        assert {:ok, status} = Fivetrex.Connectors.get_sync_status(client, connector_id)
        assert %SyncStatus{} = status

        # sync_state should be populated for any connector
        assert is_binary(status.sync_state) or is_nil(status.sync_state)

        # At least one of succeeded_at or failed_at should be populated for an active connector
        # (though a brand new connector might have neither)
        has_timing_info = status.succeeded_at != nil or status.failed_at != nil

        if has_timing_info do
          IO.puts("\n    [INFO] Last succeeded_at: #{status.succeeded_at || "nil"}")
          IO.puts("    [INFO] Last failed_at: #{status.failed_at || "nil"}")
        else
          IO.puts("\n    [INFO] No timing info available - connector may not have synced yet")
        end

        # Test helper functions on real data
        syncing = SyncStatus.syncing?(status)
        paused = SyncStatus.paused?(status)
        scheduled = SyncStatus.scheduled?(status)

        # All helper functions should return booleans
        assert is_boolean(syncing)
        assert is_boolean(paused)
        assert is_boolean(scheduled)

        IO.puts("    [INFO] Current sync_state: #{status.sync_state}")
        IO.puts("    [INFO] syncing?: #{syncing}, paused?: #{paused}, scheduled?: #{scheduled}")
      end
    end

    @tag :requires_connector
    test "sets sync frequency", %{client: client, connector_id: connector_id} do
      if is_nil(connector_id) do
        IO.puts("\n    #{@no_connector_message}")
      else
        # Get initial connector to save original sync_frequency
        {:ok, initial} = Fivetrex.Connectors.get(client, connector_id)
        original_frequency = initial.sync_frequency

        try do
          # Try to set sync frequency to 60 minutes (hourly)
          case Fivetrex.Connectors.set_sync_frequency(client, connector_id, 60) do
            {:ok, updated} ->
              assert %Connector{} = updated
              assert updated.sync_frequency == 60
              IO.puts("\n    [INFO] Successfully updated sync_frequency to 60 minutes")

            {:error, %Fivetrex.Error{} = error} ->
              # Some connectors have restrictions on frequency changes
              IO.puts(
                "\n    [INFO] set_sync_frequency failed with #{error.type}: #{error.message}"
              )

              IO.puts("    [INFO] This may be expected for some connector types or plans")
          end
        after
          # Restore original sync_frequency if it was different
          if original_frequency && original_frequency != 60 do
            case Fivetrex.Connectors.set_sync_frequency(
                   client,
                   connector_id,
                   original_frequency
                 ) do
              {:ok, _} ->
                IO.puts(
                  "    [INFO] Restored original sync_frequency: #{original_frequency} minutes"
                )

              {:error, _} ->
                IO.puts(
                  "    [WARN] Could not restore original sync_frequency: #{original_frequency}"
                )
            end
          end
        end
      end
    end

    test "returns not_found for non-existent connector sync status", %{client: client} do
      non_existent_id = "non_existent_connector_12345"

      assert {:error, %Fivetrex.Error{type: :not_found}} =
               Fivetrex.Connectors.get_sync_status(client, non_existent_id)
    end
  end

  # NOTE: Schema configuration integration tests removed.
  # Schema config is only available for database-type connectors (postgres, mysql, etc.)
  # which require external credentials and a configured destination.
  # The unit tests in test/fivetrex/connectors_test.exs provide full coverage
  # of the schema config parsing logic using Bypass mocks.
end
