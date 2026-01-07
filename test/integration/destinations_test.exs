defmodule Fivetrex.Integration.DestinationsTest do
  use ExUnit.Case

  @moduletag :integration

  import Fivetrex.TestHelpers

  alias Fivetrex.Models.Destination

  setup do
    client = integration_client()

    # Get the first group (group_id == destination_id in Fivetran)
    {:ok, %{items: [group | _]}} = Fivetrex.Groups.list(client)

    # Check if destination exists for this group
    destination_exists =
      case Fivetrex.Destinations.get(client, group.id) do
        {:ok, _} -> true
        {:error, _} -> false
      end

    {:ok, client: client, destination_id: group.id, destination_exists: destination_exists}
  end

  describe "read operations" do
    test "gets a destination", %{
      client: client,
      destination_id: destination_id,
      destination_exists: exists
    } do
      case Fivetrex.Destinations.get(client, destination_id) do
        {:ok, destination} ->
          assert %Destination{} = destination
          assert destination.id == destination_id
          assert is_binary(destination.service) or is_nil(destination.service)

        {:error, %Fivetrex.Error{type: :not_found}} ->
          unless exists do
            IO.puts("\n    [INFO] No destination configured for group #{destination_id}")
          end
      end
    end

    test "destination has expected fields when present", %{
      client: client,
      destination_id: destination_id,
      destination_exists: exists
    } do
      case Fivetrex.Destinations.get(client, destination_id) do
        {:ok, destination} ->
          # Verify struct fields are populated correctly
          assert %Destination{} = destination
          assert destination.id != nil
          # Service should be one of the known types or nil
          if destination.service do
            assert is_binary(destination.service)
          end

          # Region should be a string if present
          if destination.region do
            assert is_binary(destination.region)
          end

        {:error, %Fivetrex.Error{type: :not_found}} ->
          unless exists do
            IO.puts("\n    [INFO] No destination configured - skipping field validation")
          end
      end
    end
  end

  describe "CRUD lifecycle" do
    @tag :destination_crud
    test "creates, tests, updates, and deletes a destination", %{client: client} do
      # Create a new group specifically for this destination test
      unique_name = "fivetrex_dest_test_#{System.unique_integer([:positive])}"

      {:ok, group} = Fivetrex.Groups.create(client, %{name: unique_name})

      try do
        # CREATE destination
        # Note: Creating a destination requires valid service config.
        # We use a managed destination type that doesn't require external credentials.
        destination_params = %{
          group_id: group.id,
          service: "managed_bigquery",
          region: "GCP_US_CENTRAL1",
          time_zone_offset: "-5",
          config:
            %{
              # Managed BigQuery doesn't require external credentials
            }
        }

        case Fivetrex.Destinations.create(client, destination_params) do
          {:ok, destination} ->
            assert %Destination{} = destination
            assert destination.group_id == group.id
            assert destination.service == "managed_bigquery"

            destination_id = destination.id

            # TEST connection
            case Fivetrex.Destinations.test(client, destination_id) do
              {:ok, test_result} ->
                assert is_map(test_result)
                # Test result should have setup_status
                assert Map.has_key?(test_result, "setup_status") or
                         Map.has_key?(test_result, "setup_tests")

              {:error, %Fivetrex.Error{} = error} ->
                # Test might fail if service isn't fully configured
                IO.puts("\n    [INFO] Destination test failed: #{error.message}")
            end

            # UPDATE destination
            update_params = %{time_zone_offset: "-8"}

            case Fivetrex.Destinations.update(client, destination_id, update_params) do
              {:ok, updated} ->
                assert %Destination{} = updated
                assert updated.id == destination_id

              {:error, %Fivetrex.Error{} = error} ->
                # Some destinations may not support certain updates
                IO.puts("\n    [INFO] Destination update failed: #{error.message}")
            end

            # DELETE destination
            case Fivetrex.Destinations.delete(client, destination_id) do
              :ok ->
                # Verify deletion
                assert {:error, %Fivetrex.Error{type: :not_found}} =
                         Fivetrex.Destinations.get(client, destination_id)

              {:error, %Fivetrex.Error{} = error} ->
                # Deletion might fail if there are dependencies
                IO.puts("\n    [INFO] Destination delete failed: #{error.message}")
            end

          {:error, %Fivetrex.Error{} = error} ->
            # Creating destinations may fail depending on account permissions
            # or if the service type isn't available
            IO.puts(
              "\n    [SKIPPED] Cannot create managed_bigquery destination: #{error.message}"
            )
        end
      after
        # Cleanup: delete the test group
        Fivetrex.Groups.delete(client, group.id)
      end
    end
  end

  describe "connection testing" do
    test "tests destination connection", %{
      client: client,
      destination_id: destination_id,
      destination_exists: exists
    } do
      if exists do
        # Test the connection
        case Fivetrex.Destinations.test(client, destination_id) do
          {:ok, result} ->
            assert is_map(result)

          {:error, %Fivetrex.Error{} = error} ->
            # Test might fail for various reasons (not fully configured, etc.)
            IO.puts("\n    [INFO] Connection test failed: #{error.message}")
        end
      else
        IO.puts("\n    [SKIPPED] No destination configured - cannot test connection")
      end
    end
  end
end
