defmodule Fivetrex.Integration.GroupsTest do
  use ExUnit.Case

  @moduletag :integration

  import Fivetrex.TestHelpers

  alias Fivetrex.Models.Group

  setup do
    {:ok, client: integration_client()}
  end

  describe "read operations" do
    test "lists groups from API", %{client: client} do
      assert {:ok, %{items: groups}} = Fivetrex.Groups.list(client)
      assert is_list(groups)
    end

    test "streams groups from API", %{client: client} do
      groups =
        client
        |> Fivetrex.Groups.stream()
        |> Enum.take(5)

      assert is_list(groups)
    end

    test "gets a single group", %{client: client} do
      # First get a group ID
      {:ok, %{items: [group | _]}} = Fivetrex.Groups.list(client)

      # Then fetch it by ID
      assert {:ok, fetched} = Fivetrex.Groups.get(client, group.id)
      assert %Group{} = fetched
      assert fetched.id == group.id
    end
  end

  describe "CRUD lifecycle" do
    test "creates, updates, and deletes a group", %{client: client} do
      # Generate a unique name to avoid conflicts
      # Fivetran requires names to start with letter/underscore, only letters/numbers/underscores allowed
      unique_name = "fivetrex_test_#{System.unique_integer([:positive])}"

      # CREATE
      assert {:ok, created_group} = Fivetrex.Groups.create(client, %{name: unique_name})
      assert %Group{} = created_group
      assert created_group.name == unique_name
      assert created_group.id != nil

      group_id = created_group.id

      try do
        # GET - verify creation
        assert {:ok, fetched} = Fivetrex.Groups.get(client, group_id)
        assert fetched.id == group_id
        assert fetched.name == unique_name

        # UPDATE
        updated_name = "#{unique_name}_updated"

        assert {:ok, updated_group} =
                 Fivetrex.Groups.update(client, group_id, %{name: updated_name})

        assert updated_group.name == updated_name
        assert updated_group.id == group_id

        # GET - verify update
        assert {:ok, fetched_updated} = Fivetrex.Groups.get(client, group_id)
        assert fetched_updated.name == updated_name
      after
        # DELETE - cleanup
        assert :ok = Fivetrex.Groups.delete(client, group_id)
      end

      # Verify deletion
      assert {:error, %Fivetrex.Error{type: :not_found}} = Fivetrex.Groups.get(client, group_id)
    end
  end
end
