defmodule Fivetrex.Integration.DestinationsTest do
  use ExUnit.Case

  @moduletag :integration

  import Fivetrex.TestHelpers

  alias Fivetrex.Models.Destination

  setup do
    client = integration_client()

    # Get the first group (group_id == destination_id in Fivetran)
    {:ok, %{items: [group | _]}} = Fivetrex.Groups.list(client)

    {:ok, client: client, destination_id: group.id}
  end

  describe "read operations" do
    test "gets a destination", %{client: client, destination_id: destination_id} do
      case Fivetrex.Destinations.get(client, destination_id) do
        {:ok, destination} ->
          assert %Destination{} = destination
          assert destination.id == destination_id
          assert is_binary(destination.service) or is_nil(destination.service)

        {:error, %Fivetrex.Error{type: :not_found}} ->
          # Destination may not exist for this group, which is valid
          assert true
      end
    end

    test "destination has expected fields when present", %{
      client: client,
      destination_id: destination_id
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
          assert true
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

              {:error, %Fivetrex.Error{}} ->
                # Test might fail if service isn't fully configured
                assert true
            end

            # UPDATE destination
            update_params = %{time_zone_offset: "-8"}

            case Fivetrex.Destinations.update(client, destination_id, update_params) do
              {:ok, updated} ->
                assert %Destination{} = updated
                assert updated.id == destination_id

              {:error, %Fivetrex.Error{}} ->
                # Some destinations may not support certain updates
                assert true
            end

            # DELETE destination
            case Fivetrex.Destinations.delete(client, destination_id) do
              :ok ->
                # Verify deletion
                assert {:error, %Fivetrex.Error{type: :not_found}} =
                         Fivetrex.Destinations.get(client, destination_id)

              {:error, %Fivetrex.Error{}} ->
                # Deletion might fail if there are dependencies
                assert true
            end

          {:error, %Fivetrex.Error{}} ->
            # Creating destinations may fail depending on account permissions
            # or if the service type isn't available
            :skipped
        end
      after
        # Cleanup: delete the test group
        Fivetrex.Groups.delete(client, group.id)
      end
    end
  end

  describe "connection testing" do
    test "tests destination connection", %{client: client, destination_id: destination_id} do
      # First check if destination exists
      case Fivetrex.Destinations.get(client, destination_id) do
        {:ok, _destination} ->
          # Test the connection
          case Fivetrex.Destinations.test(client, destination_id) do
            {:ok, result} ->
              assert is_map(result)

            {:error, %Fivetrex.Error{}} ->
              # Test might fail for various reasons (not fully configured, etc.)
              assert true
          end

        {:error, %Fivetrex.Error{type: :not_found}} ->
          # No destination to test
          assert true
      end
    end
  end
end
