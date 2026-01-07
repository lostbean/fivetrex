defmodule Fivetrex.ClientTest do
  use ExUnit.Case, async: true

  import Fivetrex.TestHelpers

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  describe "new/1" do
    test "creates a client with required options" do
      client = Fivetrex.client(api_key: "key", api_secret: "secret")
      assert %Fivetrex.Client{} = client
    end

    test "raises on missing api_key" do
      assert_raise KeyError, fn ->
        Fivetrex.client(api_secret: "secret")
      end
    end

    test "raises on missing api_secret" do
      assert_raise KeyError, fn ->
        Fivetrex.client(api_key: "key")
      end
    end
  end

  describe "get/3" do
    test "sends GET request with auth header", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        auth_header = Plug.Conn.get_req_header(conn, "authorization")
        expected_auth = "Basic " <> Base.encode64("test_key:test_secret")
        assert auth_header == [expected_auth]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, success_response(%{"foo" => "bar"}))
      end)

      client = client_with_bypass(bypass)

      assert {:ok, %{"code" => "Success", "data" => %{"foo" => "bar"}}} =
               Fivetrex.Client.get(client, "/test")
    end

    test "handles 401 unauthorized", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(401, error_response("Invalid API key"))
      end)

      client = client_with_bypass(bypass)
      assert {:error, %Fivetrex.Error{type: :unauthorized}} = Fivetrex.Client.get(client, "/test")
    end

    test "handles 404 not found", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, error_response("Resource not found"))
      end)

      client = client_with_bypass(bypass)
      assert {:error, %Fivetrex.Error{type: :not_found}} = Fivetrex.Client.get(client, "/test")
    end

    test "handles 429 rate limited", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.put_resp_header("retry-after", "60")
        |> Plug.Conn.resp(429, error_response("Rate limit exceeded"))
      end)

      client = client_with_bypass(bypass)

      assert {:error, %Fivetrex.Error{type: :rate_limited, retry_after: 60}} =
               Fivetrex.Client.get(client, "/test")
    end

    test "handles 500 server error", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, error_response("Internal server error"))
      end)

      client = client_with_bypass(bypass)

      assert {:error, %Fivetrex.Error{type: :server_error, status: 500}} =
               Fivetrex.Client.get(client, "/test")
    end
  end

  describe "post/3" do
    test "sends POST request with JSON body", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/test", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"name" => "test"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, success_response(%{"id" => "123"}))
      end)

      client = client_with_bypass(bypass)
      assert {:ok, _} = Fivetrex.Client.post(client, "/test", %{name: "test"})
    end
  end

  describe "patch/3" do
    test "sends PATCH request with JSON body", %{bypass: bypass} do
      Bypass.expect_once(bypass, "PATCH", "/test/123", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"name" => "updated"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, success_response(%{"id" => "123", "name" => "updated"}))
      end)

      client = client_with_bypass(bypass)
      assert {:ok, _} = Fivetrex.Client.patch(client, "/test/123", %{name: "updated"})
    end
  end

  describe "delete/2" do
    test "sends DELETE request", %{bypass: bypass} do
      Bypass.expect_once(bypass, "DELETE", "/test/123", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, success_response(%{}))
      end)

      client = client_with_bypass(bypass)
      assert {:ok, _} = Fivetrex.Client.delete(client, "/test/123")
    end
  end
end
