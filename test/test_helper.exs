# Load .env file for integration tests
".env"
|> Dotenvy.source!()
|> System.put_env()

# Exclude integration tests by default
ExUnit.configure(exclude: [:integration])

ExUnit.start()

defmodule Fivetrex.TestHelpers do
  @moduledoc """
  Test helpers for Fivetrex tests.
  """

  @doc """
  Creates a client configured to use a Bypass endpoint.
  """
  def client_with_bypass(bypass) do
    Fivetrex.client(
      api_key: "test_key",
      api_secret: "test_secret",
      base_url: endpoint_url(bypass)
    )
  end

  @doc """
  Returns the URL for a Bypass endpoint.
  """
  def endpoint_url(bypass) do
    "http://localhost:#{bypass.port}"
  end

  @doc """
  Creates a standard Fivetran API success response.
  """
  def success_response(data) do
    Jason.encode!(%{
      "code" => "Success",
      "data" => data
    })
  end

  @doc """
  Creates a standard Fivetran API list response with items.
  """
  def list_response(items, next_cursor \\ nil) do
    data =
      if next_cursor do
        %{"items" => items, "next_cursor" => next_cursor}
      else
        %{"items" => items}
      end

    success_response(data)
  end

  @doc """
  Creates an error response.
  """
  def error_response(message) do
    Jason.encode!(%{
      "code" => "Error",
      "message" => message
    })
  end

  @doc """
  Creates a client for integration tests using environment variables.
  Raises if credentials are not configured.
  """
  def integration_client do
    api_key =
      System.get_env("FIVETRAN_API_KEY") ||
        raise "FIVETRAN_API_KEY not set. Add it to .env file."

    api_secret =
      System.get_env("FIVETRAN_API_SECRET") ||
        raise "FIVETRAN_API_SECRET not set. Add it to .env file."

    Fivetrex.client(api_key: api_key, api_secret: api_secret)
  end
end
