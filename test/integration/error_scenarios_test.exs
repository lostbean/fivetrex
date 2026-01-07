defmodule Fivetrex.Integration.ErrorScenariosTest do
  use ExUnit.Case

  @moduletag :integration

  import Fivetrex.TestHelpers

  alias Fivetrex.Error

  describe "not_found errors" do
    setup do
      {:ok, client: integration_client()}
    end

    test "returns not_found for non-existent group", %{client: client} do
      fake_id = "non_existent_group_#{System.unique_integer([:positive])}"

      assert {:error, %Error{type: :not_found}} = Fivetrex.Groups.get(client, fake_id)
    end

    test "returns not_found for non-existent connector", %{client: client} do
      fake_id = "non_existent_connector_#{System.unique_integer([:positive])}"

      assert {:error, %Error{type: :not_found}} = Fivetrex.Connectors.get(client, fake_id)
    end

    test "returns not_found for non-existent destination", %{client: client} do
      fake_id = "non_existent_destination_#{System.unique_integer([:positive])}"

      assert {:error, %Error{type: :not_found}} = Fivetrex.Destinations.get(client, fake_id)
    end

    test "returns not_found when deleting non-existent group", %{client: client} do
      fake_id = "non_existent_group_#{System.unique_integer([:positive])}"

      assert {:error, %Error{type: :not_found}} = Fivetrex.Groups.delete(client, fake_id)
    end

    test "returns not_found when updating non-existent group", %{client: client} do
      fake_id = "non_existent_group_#{System.unique_integer([:positive])}"

      assert {:error, %Error{type: :not_found}} =
               Fivetrex.Groups.update(client, fake_id, %{name: "new name"})
    end
  end

  describe "unauthorized errors" do
    test "returns unauthorized with invalid credentials" do
      # Create a client with invalid credentials
      invalid_client =
        Fivetrex.client(
          api_key: "invalid_api_key",
          api_secret: "invalid_api_secret"
        )

      assert {:error, %Error{type: :unauthorized}} = Fivetrex.Groups.list(invalid_client)
    end

    test "returns unauthorized with empty credentials" do
      # Create a client with empty credentials
      invalid_client =
        Fivetrex.client(
          api_key: "",
          api_secret: ""
        )

      assert {:error, %Error{type: :unauthorized}} = Fivetrex.Groups.list(invalid_client)
    end
  end

  describe "error struct fields" do
    setup do
      {:ok, client: integration_client()}
    end

    test "not_found error has correct fields", %{client: client} do
      fake_id = "non_existent_#{System.unique_integer([:positive])}"

      {:error, error} = Fivetrex.Groups.get(client, fake_id)

      assert %Error{} = error
      assert error.type == :not_found
      assert error.status == 404
      assert is_binary(error.message)
      assert error.retry_after == nil
    end

    test "unauthorized error has correct fields" do
      invalid_client =
        Fivetrex.client(
          api_key: "invalid",
          api_secret: "invalid"
        )

      {:error, error} = Fivetrex.Groups.list(invalid_client)

      assert %Error{} = error
      assert error.type == :unauthorized
      assert error.status == 401
      assert is_binary(error.message)
    end
  end
end
