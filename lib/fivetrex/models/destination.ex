defmodule Fivetrex.Models.Destination do
  @moduledoc """
  Represents a Fivetran Destination.

  A Destination configures the target data warehouse where Fivetran will load
  synced data. Each group has exactly one destination, and all connectors in
  that group load data into this destination.

  ## Fields

    * `:id` - The unique identifier for the destination (same as the group ID)
    * `:group_id` - The ID of the parent group
    * `:service` - The destination type (e.g., `"snowflake"`, `"big_query"`, `"redshift"`)
    * `:region` - Data processing region (e.g., `"US"`, `"EU"`, `"APAC"`)
    * `:time_zone_offset` - Timezone offset as a string (e.g., `"-5"`, `"+1"`)
    * `:setup_status` - Connection status (e.g., `"connected"`, `"incomplete"`)
    * `:config` - Service-specific configuration (connection details, credentials)

  ## Supported Services

  Common destination services include:

    * `"snowflake"` - Snowflake Data Cloud
    * `"big_query"` - Google BigQuery
    * `"redshift"` - Amazon Redshift
    * `"databricks"` - Databricks Lakehouse
    * `"postgres"` - PostgreSQL (as destination)
    * `"azure_sql_database"` - Azure SQL Database
    * `"azure_synapse_analytics"` - Azure Synapse
    * `"mysql"` - MySQL (as destination)

  See Fivetran's documentation for the complete list.

  ## Configuration

  The `:config` field contains service-specific settings. For example, a
  Snowflake destination might have:

  ```elixir
  %{
    "host" => "myaccount.snowflakecomputing.com",
    "port" => 443,
    "database" => "ANALYTICS",
    "auth" => "PASSWORD",
    "user" => "FIVETRAN_USER"
    # password is not returned for security
  }
  ```

  ## Security Note

  The config map may contain sensitive information. However, Fivetran's API
  masks secrets in responses (passwords appear as `"******"`). Never log
  or expose destination configs in production.

  ## Examples

  Working with a destination:

      {:ok, destination} = Fivetrex.Destinations.get(client, "destination_id")
      IO.puts("Service: \#{destination.service}")
      IO.puts("Region: \#{destination.region}")
      IO.puts("Status: \#{destination.setup_status}")

  Pattern matching on destination type:

      case destination.service do
        "snowflake" -> configure_snowflake_settings(destination)
        "big_query" -> configure_bigquery_settings(destination)
        _ -> use_default_settings(destination)
      end

  ## See Also

    * `Fivetrex.Destinations` - API functions for managing destinations
    * `Fivetrex.Models.Group` - Parent group for destinations
  """

  @typedoc """
  A Fivetran Destination struct.

  All fields may be `nil` if not provided in the API response.
  """
  @type t :: %__MODULE__{
          id: String.t() | nil,
          group_id: String.t() | nil,
          service: String.t() | nil,
          region: String.t() | nil,
          time_zone_offset: String.t() | nil,
          setup_status: String.t() | nil,
          config: map() | nil
        }

  defstruct [
    :id,
    :group_id,
    :service,
    :region,
    :time_zone_offset,
    :setup_status,
    :config
  ]

  @doc """
  Converts a map (from JSON response) to a Destination struct.

  This function is used internally by `Fivetrex.Destinations` functions to parse
  API responses into typed structs.

  ## Parameters

    * `map` - A map with string keys from a decoded JSON response

  ## Returns

  A `%Fivetrex.Models.Destination{}` struct with fields populated from the map.

  ## Examples

      iex> map = %{
      ...>   "id" => "dest_123",
      ...>   "service" => "snowflake",
      ...>   "region" => "US",
      ...>   "setup_status" => "connected"
      ...> }
      iex> destination = Fivetrex.Models.Destination.from_map(map)
      iex> destination.service
      "snowflake"
      iex> destination.setup_status
      "connected"

  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      group_id: map["group_id"],
      service: map["service"],
      region: map["region"],
      time_zone_offset: map["time_zone_offset"],
      setup_status: map["setup_status"],
      config: map["config"]
    }
  end
end
