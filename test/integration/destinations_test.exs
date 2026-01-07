defmodule Fivetrex.Integration.DestinationsTest do
  use ExUnit.Case

  @moduletag :integration

  import Fivetrex.TestHelpers

  setup do
    client = integration_client()

    # Get the first group (group_id == destination_id in Fivetran)
    {:ok, %{items: [group | _]}} = Fivetrex.Groups.list(client)

    {:ok, client: client, destination_id: group.id}
  end

  test "gets a destination", %{client: client, destination_id: destination_id} do
    case Fivetrex.Destinations.get(client, destination_id) do
      {:ok, destination} ->
        assert destination.id == destination_id

      {:error, %Fivetrex.Error{type: :not_found}} ->
        # Destination may not exist for this group, which is valid
        assert true
    end
  end
end
