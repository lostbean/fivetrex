defmodule Fivetrex.Destinations do
  @moduledoc """
  Functions for managing Fivetran Destinations.

  A Destination configures the target data warehouse where Fivetran will load
  synced data. Each group has exactly one destination. Supported destination
  types include Snowflake, BigQuery, Redshift, Databricks, and many others.

  ## Overview

  Destinations are the "where" of Fivetran - they define where your data lands.
  Each destination:
    * Belongs to a single group
    * Has a service type (e.g., "snowflake", "big_query")
    * Contains credentials and connection information
    * Has a region for data processing

  ## Common Operations

  ### Get a Destination

      {:ok, destination} = Fivetrex.Destinations.get(client, "destination_id")

  ### Create a Destination

      {:ok, destination} = Fivetrex.Destinations.create(client, %{
        group_id: "group_id",
        service: "snowflake",
        region: "US",
        time_zone_offset: "-5",
        config: %{...}
      })

  ### Test Connection

      {:ok, result} = Fivetrex.Destinations.test(client, "destination_id")

  ## Supported Services

  Common destination services include:
    * `"snowflake"` - Snowflake Data Cloud
    * `"big_query"` - Google BigQuery
    * `"redshift"` - Amazon Redshift
    * `"databricks"` - Databricks Lakehouse
    * `"postgres"` - PostgreSQL
    * `"azure_sql_database"` - Azure SQL Database

  See Fivetran's documentation for the full list and configuration options.

  ## Security Note

  Destination configurations contain sensitive credentials. Always:
    * Store credentials securely (environment variables, secrets manager)
    * Use least-privilege database users
    * Rotate credentials periodically

  ## See Also

    * `Fivetrex.Models.Destination` - The Destination struct
    * `Fivetrex.Groups` - Managing groups that contain destinations
  """

  alias Fivetrex.Client
  alias Fivetrex.Models.Destination

  @doc """
  Gets a destination by its ID.

  ## Parameters

    * `client` - The Fivetrex client
    * `destination_id` - The unique identifier of the destination

  ## Returns

    * `{:ok, Destination.t()}` - The destination
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, destination} = Fivetrex.Destinations.get(client, "destination_id")
      IO.puts("Service: \#{destination.service}")
      IO.puts("Region: \#{destination.region}")

  """
  @spec get(Client.t(), String.t()) :: {:ok, Destination.t()} | {:error, Fivetrex.Error.t()}
  def get(client, destination_id) do
    case Client.get(client, "/destinations/#{destination_id}") do
      {:ok, %{"data" => data}} ->
        {:ok, Destination.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Creates a new destination.

  The configuration options are highly dependent on the destination service type.
  See Fivetran's documentation for service-specific options.

  ## Parameters

    * `client` - The Fivetrex client
    * `params` - A map containing:
      * `:group_id` - Required. The group to create the destination in.
      * `:service` - Required. The destination type (e.g., "snowflake", "big_query").
      * `:region` - Required. Data processing location (e.g., "US", "EU").
      * `:time_zone_offset` - Required. Timezone offset as string (e.g., "-5", "+1").
      * `:config` - Required. Service-specific configuration.

  ## Returns

    * `{:ok, Destination.t()}` - The created destination
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

  Create a Snowflake destination:

      {:ok, destination} = Fivetrex.Destinations.create(client, %{
        group_id: "group_id",
        service: "snowflake",
        region: "US",
        time_zone_offset: "-5",
        config: %{
          host: "myaccount.snowflakecomputing.com",
          port: 443,
          database: "ANALYTICS",
          auth: "PASSWORD",
          user: "FIVETRAN_USER",
          password: System.get_env("SNOWFLAKE_PASSWORD")
        }
      })

  Create a BigQuery destination:

      {:ok, destination} = Fivetrex.Destinations.create(client, %{
        group_id: "group_id",
        service: "big_query",
        region: "US",
        time_zone_offset: "-8",
        config: %{
          project_id: "my-gcp-project",
          data_set_location: "US"
        }
      })

  """
  @spec create(Client.t(), map()) :: {:ok, Destination.t()} | {:error, Fivetrex.Error.t()}
  def create(client, params) do
    case Client.post(client, "/destinations", params) do
      {:ok, %{"data" => data}} ->
        {:ok, Destination.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Updates an existing destination.

  Use this to modify destination configuration, such as updating credentials
  or changing connection settings.

  ## Parameters

    * `client` - The Fivetrex client
    * `destination_id` - The ID of the destination to update
    * `params` - A map with fields to update:
      * `:region` - Updated region
      * `:time_zone_offset` - Updated timezone offset
      * `:config` - Updated configuration (merged with existing)

  ## Returns

    * `{:ok, Destination.t()}` - The updated destination
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

  Update credentials:

      {:ok, destination} = Fivetrex.Destinations.update(client, "destination_id", %{
        config: %{
          password: System.get_env("NEW_PASSWORD")
        }
      })

  Change region:

      {:ok, destination} = Fivetrex.Destinations.update(client, "destination_id", %{
        region: "EU"
      })

  """
  @spec update(Client.t(), String.t(), map()) ::
          {:ok, Destination.t()} | {:error, Fivetrex.Error.t()}
  def update(client, destination_id, params) do
    case Client.patch(client, "/destinations/#{destination_id}", params) do
      {:ok, %{"data" => data}} ->
        {:ok, Destination.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Deletes a destination.

  **Warning:** You cannot delete a destination that has connectors. Delete all
  connectors first, or delete the entire group.

  ## Parameters

    * `client` - The Fivetrex client
    * `destination_id` - The ID of the destination to delete

  ## Returns

    * `:ok` - On successful deletion
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      :ok = Fivetrex.Destinations.delete(client, "destination_id")

  """
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Fivetrex.Error.t()}
  def delete(client, destination_id) do
    case Client.delete(client, "/destinations/#{destination_id}") do
      {:ok, _} ->
        :ok

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Runs connection tests for a destination.

  This validates that Fivetran can connect to your destination warehouse with
  the provided credentials. Use this after creating or updating a destination
  to verify the configuration is correct.

  ## Parameters

    * `client` - The Fivetrex client
    * `destination_id` - The ID of the destination to test

  ## Returns

    * `{:ok, map()}` - Test results including:
      * `"setup_status"` - Overall status (e.g., "connected", "incomplete")
      * `"tests"` - List of individual test results

    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, result} = Fivetrex.Destinations.test(client, "destination_id")

      case result["setup_status"] do
        "connected" ->
          IO.puts("Destination is properly configured!")

        status ->
          IO.puts("Setup status: \#{status}")
          IO.inspect(result["tests"], label: "Test results")
      end

  """
  @spec test(Client.t(), String.t()) :: {:ok, map()} | {:error, Fivetrex.Error.t()}
  def test(client, destination_id) do
    case Client.post(client, "/destinations/#{destination_id}/test") do
      {:ok, %{"data" => data}} ->
        {:ok, data}

      {:error, _} = error ->
        error
    end
  end
end
