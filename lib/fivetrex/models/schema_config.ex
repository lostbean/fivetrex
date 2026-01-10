defmodule Fivetrex.Models.SchemaConfig do
  @moduledoc """
  Represents the schema configuration for a Fivetran connector.

  Schema configuration controls which schemas, tables, and columns are synced
  from your data source to your destination. This struct contains the hierarchical
  configuration of all database objects.

  ## Structure

  The configuration follows a nested hierarchy:

      SchemaConfig
        └── schemas (map of Schema by name)
              └── tables (map of Table by name)
                    └── columns (map of Column by name)

  ## Fields

    * `:enable_new_by_default` - Whether newly discovered schemas/tables are
      enabled by default
    * `:schema_change_handling` - How to handle schema changes:
      * `"ALLOW_ALL"` - All new schemas/tables/columns are included
      * `"ALLOW_COLUMNS"` - New schemas/tables excluded, new columns included
      * `"BLOCK_ALL"` - All new items excluded from syncs
    * `:schemas` - Map of schema name to `Fivetrex.Models.Schema` structs

  ## Examples

  Working with schema configuration:

      {:ok, config} = Fivetrex.Connectors.get_schema_config(client, "connector_id")

      # Iterate through enabled schemas
      for {name, schema} <- config.schemas, schema.enabled do
        IO.puts("Schema: \#{name}")

        for {table_name, table} <- schema.tables, table.enabled do
          IO.puts("  Table: \#{table_name}")
        end
      end

  ## See Also

    * `Fivetrex.Connectors.get_schema_config/2` - Fetch schema configuration
    * `Fivetrex.Connectors.update_schema_config/3` - Modify schema configuration
    * `Fivetrex.Models.Schema` - Individual schema struct
  """

  alias Fivetrex.Models.Schema

  @typedoc """
  A Fivetran Schema Configuration struct.

  All fields may be `nil` if not provided in the API response.
  """
  @type t :: %__MODULE__{
          enable_new_by_default: boolean() | nil,
          schema_change_handling: String.t() | nil,
          schemas: %{String.t() => Schema.t()} | nil
        }

  defstruct [:enable_new_by_default, :schema_change_handling, :schemas]

  @doc """
  Converts a map (from JSON response) to a SchemaConfig struct.

  Recursively parses nested schemas, tables, and columns.

  ## Parameters

    * `map` - A map with string keys from a decoded JSON response

  ## Returns

  A `%Fivetrex.Models.SchemaConfig{}` struct with nested Schema structs.

  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    schemas =
      case map["schemas"] do
        nil ->
          nil

        schemas_map when is_map(schemas_map) ->
          Map.new(schemas_map, fn {name, schema_data} ->
            {name, Schema.from_map(schema_data)}
          end)
      end

    %__MODULE__{
      enable_new_by_default: map["enable_new_by_default"],
      schema_change_handling: map["schema_change_handling"],
      schemas: schemas
    }
  end
end

defmodule Fivetrex.Models.Schema do
  @moduledoc """
  Represents a database schema within a connector's schema configuration.

  A schema is a namespace containing tables. In some databases (e.g., PostgreSQL),
  this maps directly to database schemas. In others (e.g., MySQL), it may represent
  a database name.

  ## Fields

    * `:name_in_destination` - The name used in the destination warehouse
      (may differ from source due to Fivetran naming rules)
    * `:enabled` - Whether this schema is being synced
    * `:tables` - Map of table name to `Fivetrex.Models.Table` structs

  ## Examples

      # Check if a schema is enabled
      if schema.enabled do
        IO.puts("Syncing schema: \#{schema.name_in_destination}")
      end

      # Get all enabled tables
      enabled_tables =
        schema.tables
        |> Enum.filter(fn {_name, table} -> table.enabled end)
        |> Map.new()

  """

  alias Fivetrex.Models.Table

  @typedoc """
  A Fivetran Schema struct.

  All fields may be `nil` if not provided in the API response.
  """
  @type t :: %__MODULE__{
          name_in_destination: String.t() | nil,
          enabled: boolean() | nil,
          tables: %{String.t() => Table.t()} | nil
        }

  defstruct [:name_in_destination, :enabled, :tables]

  @doc """
  Converts a map (from JSON response) to a Schema struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    tables =
      case map["tables"] do
        nil ->
          nil

        tables_map when is_map(tables_map) ->
          Map.new(tables_map, fn {name, table_data} ->
            {name, Table.from_map(table_data)}
          end)
      end

    %__MODULE__{
      name_in_destination: map["name_in_destination"],
      enabled: map["enabled"],
      tables: tables
    }
  end
end

defmodule Fivetrex.Models.Table do
  @moduledoc """
  Represents a table within a schema configuration.

  Tables contain the actual data being synced. Each table can have its own
  sync mode and column configuration.

  ## Fields

    * `:name_in_destination` - The name used in the destination warehouse
    * `:enabled` - Whether this table is being synced
    * `:sync_mode` - How data changes are handled:
      * `"SOFT_DELETE"` - Deleted rows are marked with `_fivetran_deleted`
      * `"HISTORY"` - Historical tracking with `_fivetran_start`/`_fivetran_end`
      * `"LIVE"` - Real-time sync (deletes are hard deletes)
    * `:supports_columns_config` - Whether per-column configuration is supported
    * `:enabled_patch_settings` - Advanced patch settings
    * `:columns` - Map of column name to `Fivetrex.Models.Column` structs

  ## Sync Modes

  The sync mode determines how Fivetran handles data modifications:

  | Mode | Inserts | Updates | Deletes |
  |------|---------|---------|---------|
  | SOFT_DELETE | Appended | In-place | Marked with flag |
  | HISTORY | New row | New row | End timestamp set |
  | LIVE | Appended | In-place | Hard deleted |

  ## Examples

      # Check sync mode
      case table.sync_mode do
        "SOFT_DELETE" -> "Deleted rows are marked, not removed"
        "HISTORY" -> "Full history is preserved"
        "LIVE" -> "Deletes are permanent"
      end

  """

  alias Fivetrex.Models.Column

  @typedoc """
  A Fivetran Table struct.

  All fields may be `nil` if not provided in the API response.
  """
  @type t :: %__MODULE__{
          name_in_destination: String.t() | nil,
          enabled: boolean() | nil,
          sync_mode: String.t() | nil,
          supports_columns_config: boolean() | nil,
          enabled_patch_settings: map() | nil,
          columns: %{String.t() => Column.t()} | nil
        }

  defstruct [
    :name_in_destination,
    :enabled,
    :sync_mode,
    :supports_columns_config,
    :enabled_patch_settings,
    :columns
  ]

  @doc """
  Converts a map (from JSON response) to a Table struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    columns =
      case map["columns"] do
        nil ->
          nil

        columns_map when is_map(columns_map) ->
          Map.new(columns_map, fn {name, column_data} ->
            {name, Column.from_map(column_data)}
          end)
      end

    %__MODULE__{
      name_in_destination: map["name_in_destination"],
      enabled: map["enabled"],
      sync_mode: map["sync_mode"],
      supports_columns_config: map["supports_columns_config"],
      enabled_patch_settings: map["enabled_patch_settings"],
      columns: columns
    }
  end
end

defmodule Fivetrex.Models.Column do
  @moduledoc """
  Represents a column within a table configuration.

  Columns are the individual fields being synced from source to destination.
  Each column can be independently enabled/disabled or hashed for privacy.

  ## Fields

    * `:name_in_destination` - The name used in the destination warehouse
    * `:enabled` - Whether this column is being synced
    * `:hashed` - Whether the column value is hashed for privacy
      (useful for PII like emails)
    * `:is_primary_key` - Whether this column is part of the primary key
    * `:type` - The Fivetran source data type (e.g., "STRING", "INTEGER",
      "TIMESTAMP", "FLOAT", "BOOLEAN", "DATE", etc.)
    * `:enabled_patch_settings` - Advanced patch settings

  ## Privacy Hashing

  When `:hashed` is true, Fivetran applies a one-way hash to column values.
  This is useful for:

    * Removing personally identifiable information (PII)
    * Maintaining referential integrity while anonymizing data
    * Compliance with privacy regulations (GDPR, CCPA)

  ## Examples

      # Find primary key columns
      primary_keys =
        columns
        |> Enum.filter(fn {_name, col} -> col.is_primary_key end)
        |> Enum.map(fn {name, _col} -> name end)

      # Find hashed (anonymized) columns
      hashed_columns =
        columns
        |> Enum.filter(fn {_name, col} -> col.hashed end)
        |> Enum.map(fn {name, _col} -> name end)

  """

  @typedoc """
  A Fivetran Column struct.

  All fields may be `nil` if not provided in the API response.
  """
  @type t :: %__MODULE__{
          name_in_destination: String.t() | nil,
          enabled: boolean() | nil,
          hashed: boolean() | nil,
          is_primary_key: boolean() | nil,
          type: String.t() | nil,
          enabled_patch_settings: map() | nil
        }

  defstruct [
    :name_in_destination,
    :enabled,
    :hashed,
    :is_primary_key,
    :type,
    :enabled_patch_settings
  ]

  @doc """
  Converts a map (from JSON response) to a Column struct.
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      name_in_destination: map["name_in_destination"],
      enabled: map["enabled"],
      hashed: map["hashed"],
      is_primary_key: map["is_primary_key"],
      type: map["type"],
      enabled_patch_settings: map["enabled_patch_settings"]
    }
  end
end
