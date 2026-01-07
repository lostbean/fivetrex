defmodule Fivetrex.GroupsTest do
  use ExUnit.Case, async: true

  import Fivetrex.TestHelpers

  alias Fivetrex.Groups
  alias Fivetrex.Models.Group

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, client: client_with_bypass(bypass)}
  end

  describe "list/2" do
    test "returns groups", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/groups", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          list_response([
            %{"id" => "g1", "name" => "Group 1", "created_at" => "2024-01-01T00:00:00Z"},
            %{"id" => "g2", "name" => "Group 2", "created_at" => "2024-01-02T00:00:00Z"}
          ])
        )
      end)

      assert {:ok, %{items: groups, next_cursor: nil}} = Groups.list(client)
      assert length(groups) == 2
      assert [%Group{id: "g1"}, %Group{id: "g2"}] = groups
    end

    test "handles pagination", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/groups", fn conn ->
        assert conn.query_params["cursor"] == "abc123"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          list_response([
            %{"id" => "g3", "name" => "Group 3"}
          ])
        )
      end)

      assert {:ok, %{items: [%Group{id: "g3"}], next_cursor: nil}} =
               Groups.list(client, cursor: "abc123")
    end

    test "returns next_cursor when present", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/groups", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          list_response(
            [
              %{"id" => "g1", "name" => "Group 1"}
            ],
            "next_page_cursor"
          )
        )
      end)

      assert {:ok, %{items: _, next_cursor: "next_page_cursor"}} = Groups.list(client)
    end
  end

  describe "stream/2" do
    test "streams through multiple pages", %{bypass: bypass, client: client} do
      call_count = :counters.new(1, [:atomics])

      Bypass.expect(bypass, "GET", "/groups", fn conn ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        response =
          case {count, conn.query_params["cursor"]} do
            {1, nil} ->
              list_response([%{"id" => "g1", "name" => "Group 1"}], "cursor1")

            {2, "cursor1"} ->
              list_response([%{"id" => "g2", "name" => "Group 2"}], "cursor2")

            {3, "cursor2"} ->
              list_response([%{"id" => "g3", "name" => "Group 3"}])
          end

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, response)
      end)

      groups =
        client
        |> Groups.stream()
        |> Enum.to_list()

      assert length(groups) == 3
      assert Enum.map(groups, & &1.id) == ["g1", "g2", "g3"]
    end
  end

  describe "get/2" do
    test "returns a group", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/groups/g1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "g1",
            "name" => "My Group",
            "created_at" => "2024-01-01T00:00:00Z"
          })
        )
      end)

      assert {:ok, %Group{id: "g1", name: "My Group"}} = Groups.get(client, "g1")
    end

    test "returns error for non-existent group", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/groups/nonexistent", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, error_response("Group not found"))
      end)

      assert {:error, %Fivetrex.Error{type: :not_found}} = Groups.get(client, "nonexistent")
    end
  end

  describe "create/2" do
    test "creates a group", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/groups", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"name" => "New Group"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "new_id",
            "name" => "New Group",
            "created_at" => "2024-01-01T00:00:00Z"
          })
        )
      end)

      assert {:ok, %Group{id: "new_id", name: "New Group"}} =
               Groups.create(client, %{name: "New Group"})
    end
  end

  describe "update/3" do
    test "updates a group", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/groups/g1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"name" => "Updated Name"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "g1",
            "name" => "Updated Name"
          })
        )
      end)

      assert {:ok, %Group{name: "Updated Name"}} =
               Groups.update(client, "g1", %{name: "Updated Name"})
    end
  end

  describe "delete/2" do
    test "deletes a group", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "DELETE", "/groups/g1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, success_response(%{}))
      end)

      assert :ok = Groups.delete(client, "g1")
    end
  end
end
