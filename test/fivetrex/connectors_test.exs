defmodule Fivetrex.ConnectorsTest do
  use ExUnit.Case, async: true

  import Fivetrex.TestHelpers

  alias Fivetrex.Connectors
  alias Fivetrex.Models.Connector

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, client: client_with_bypass(bypass)}
  end

  describe "list/3" do
    test "returns connectors in a group", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/groups/g1/connectors", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          list_response([
            %{
              "id" => "c1",
              "group_id" => "g1",
              "service" => "postgres",
              "paused" => false,
              "status" => %{"sync_state" => "scheduled"}
            },
            %{
              "id" => "c2",
              "group_id" => "g1",
              "service" => "salesforce",
              "paused" => true,
              "status" => %{"sync_state" => "paused"}
            }
          ])
        )
      end)

      assert {:ok, %{items: connectors, next_cursor: nil}} = Connectors.list(client, "g1")
      assert length(connectors) == 2
      assert [%Connector{id: "c1", service: "postgres"}, %Connector{id: "c2"}] = connectors
    end
  end

  describe "get/2" do
    test "returns a connector", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/connectors/c1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "c1",
            "group_id" => "g1",
            "service" => "postgres",
            "paused" => false,
            "status" => %{"sync_state" => "syncing"}
          })
        )
      end)

      assert {:ok, %Connector{id: "c1", service: "postgres"}} = Connectors.get(client, "c1")
    end
  end

  describe "create/2" do
    test "creates a connector", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/connectors", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["group_id"] == "g1"
        assert decoded["service"] == "postgres"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "new_connector",
            "group_id" => "g1",
            "service" => "postgres"
          })
        )
      end)

      assert {:ok, %Connector{id: "new_connector"}} =
               Connectors.create(client, %{
                 group_id: "g1",
                 service: "postgres",
                 config: %{host: "localhost"}
               })
    end
  end

  describe "update/3" do
    test "updates a connector", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/connectors/c1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"paused" => true}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "c1",
            "paused" => true
          })
        )
      end)

      assert {:ok, %Connector{paused: true}} =
               Connectors.update(client, "c1", %{paused: true})
    end
  end

  describe "delete/2" do
    test "deletes a connector", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "DELETE", "/connectors/c1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, success_response(%{}))
      end)

      assert :ok = Connectors.delete(client, "c1")
    end
  end

  describe "sync/2" do
    test "triggers a sync", %{bypass: bypass, client: client} do
      # Real Fivetran API returns {"code": "Success", "message": "..."} for sync
      response = Jason.encode!(%{"code" => "Success", "message" => "Sync triggered"})

      Bypass.expect_once(bypass, "POST", "/connectors/c1/sync", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, response)
      end)

      assert {:ok, %{"code" => "Success", "message" => "Sync triggered"}} =
               Connectors.sync(client, "c1")
    end
  end

  describe "resync!/3" do
    test "requires confirmation", %{client: client} do
      assert_raise ArgumentError, ~r/confirm: true/, fn ->
        Connectors.resync!(client, "c1", [])
      end
    end

    test "triggers resync with confirmation", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/connectors/c1/resync", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, success_response(%{"syncing" => true}))
      end)

      assert {:ok, _} = Connectors.resync!(client, "c1", confirm: true)
    end
  end

  describe "get_state/2" do
    test "returns connector state", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/connectors/c1/state", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "state" => %{"cursor" => "abc123"}
          })
        )
      end)

      assert {:ok, %{"state" => %{"cursor" => "abc123"}}} = Connectors.get_state(client, "c1")
    end
  end

  describe "pause/2" do
    test "pauses a connector", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/connectors/c1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"paused" => true}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "c1",
            "paused" => true
          })
        )
      end)

      assert {:ok, %Connector{paused: true}} = Connectors.pause(client, "c1")
    end
  end

  describe "resume/2" do
    test "resumes a connector", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/connectors/c1", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"paused" => false}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "c1",
            "paused" => false
          })
        )
      end)

      assert {:ok, %Connector{paused: false}} = Connectors.resume(client, "c1")
    end
  end
end

defmodule Fivetrex.Models.ConnectorTest do
  use ExUnit.Case, async: true

  alias Fivetrex.Models.Connector

  describe "sync_state/1" do
    test "returns sync state from status" do
      connector = %Connector{status: %{"sync_state" => "syncing"}}
      assert Connector.sync_state(connector) == "syncing"
    end

    test "returns nil when no status" do
      connector = %Connector{status: nil}
      assert Connector.sync_state(connector) == nil
    end
  end

  describe "syncing?/1" do
    test "returns true when syncing" do
      connector = %Connector{status: %{"sync_state" => "syncing"}}
      assert Connector.syncing?(connector)
    end

    test "returns false when not syncing" do
      connector = %Connector{status: %{"sync_state" => "scheduled"}}
      refute Connector.syncing?(connector)
    end
  end

  describe "paused?/1" do
    test "returns true when paused" do
      connector = %Connector{paused: true}
      assert Connector.paused?(connector)
    end

    test "returns false when not paused" do
      connector = %Connector{paused: false}
      refute Connector.paused?(connector)
    end
  end
end
