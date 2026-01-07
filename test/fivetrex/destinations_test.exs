defmodule Fivetrex.DestinationsTest do
  use ExUnit.Case, async: true

  import Fivetrex.TestHelpers

  alias Fivetrex.Destinations
  alias Fivetrex.Models.Destination

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, client: client_with_bypass(bypass)}
  end

  describe "get/2" do
    test "returns a destination", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "GET", "/destinations/d1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "d1",
            "group_id" => "g1",
            "service" => "snowflake",
            "region" => "US",
            "setup_status" => "connected"
          })
        )
      end)

      assert {:ok, %Destination{id: "d1", service: "snowflake"}} =
               Destinations.get(client, "d1")
    end
  end

  describe "create/2" do
    test "creates a destination", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/destinations", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["group_id"] == "g1"
        assert decoded["service"] == "snowflake"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "new_dest",
            "group_id" => "g1",
            "service" => "snowflake"
          })
        )
      end)

      assert {:ok, %Destination{id: "new_dest"}} =
               Destinations.create(client, %{
                 group_id: "g1",
                 service: "snowflake",
                 region: "US",
                 time_zone_offset: "-5",
                 config: %{host: "account.snowflake.com"}
               })
    end
  end

  describe "update/3" do
    test "updates a destination", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "PATCH", "/destinations/d1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "id" => "d1",
            "service" => "snowflake",
            "region" => "EU"
          })
        )
      end)

      assert {:ok, %Destination{region: "EU"}} =
               Destinations.update(client, "d1", %{region: "EU"})
    end
  end

  describe "delete/2" do
    test "deletes a destination", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "DELETE", "/destinations/d1", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, success_response(%{}))
      end)

      assert :ok = Destinations.delete(client, "d1")
    end
  end

  describe "test/2" do
    test "runs destination tests", %{bypass: bypass, client: client} do
      Bypass.expect_once(bypass, "POST", "/destinations/d1/test", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          success_response(%{
            "setup_status" => "connected",
            "tests" => [
              %{"name" => "connection", "status" => "PASSED"}
            ]
          })
        )
      end)

      assert {:ok, %{"setup_status" => "connected"}} = Destinations.test(client, "d1")
    end
  end
end
