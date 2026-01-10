defmodule Fivetrex.SyncLogs do
  @moduledoc """
  Documentation for accessing Fivetran sync logs via your data warehouse.

  Fivetran does not provide a REST API for accessing sync logs. Instead, sync
  logs and operational metadata are available through the Fivetran Platform
  Connector, which syncs this data directly to your data warehouse.

  ## Overview

  To access sync logs, you need to set up the Fivetran Platform Connector:

  1. Create a new connector in your Fivetran dashboard
  2. Select "Fivetran Platform" as the source type
  3. Configure it to sync to your destination warehouse
  4. The connector will populate metadata tables with sync history

  ## Schema Location

  By default, Fivetran Platform Connector data is stored in a schema named
  `fivetran_metadata` (or `fivetran_log` for legacy setups). The schema name
  is configurable when setting up the connector.

  ## Key Tables

  The Fivetran Platform Connector provides several tables:

  ### LOG

  The primary table for sync event logs. Contains:

    * `id` - Unique log entry identifier
    * `connector_id` - The connector that generated the log
    * `event` - Event type (e.g., "sync_start", "sync_end", "write_to_table")
    * `message_event` - Detailed event category
    * `message_data` - JSON with event-specific details
    * `time_stamp` - When the event occurred

  ### CONNECTOR_SDK_LOG

  Logs from SDK-based connectors (custom connectors). Contains:

    * `connector_id` - The SDK connector ID
    * `log_message` - The log message text
    * `log_level` - Log severity (INFO, WARNING, ERROR)
    * `time_stamp` - When the log was generated

  ### AUDIT_TRAIL

  Account-level audit events. Contains:

    * `id` - Unique audit entry identifier
    * `actor` - Who performed the action
    * `action` - What action was performed
    * `object_type` - Type of object affected
    * `object_id` - ID of the affected object
    * `time_stamp` - When the action occurred

  ## Example SQL Queries

  ### Recent Sync Events

  Get the last 10 sync events for a specific connector:

      SELECT
        time_stamp,
        event,
        message_event,
        message_data
      FROM fivetran_metadata.log
      WHERE connector_id = 'your_connector_id'
      ORDER BY time_stamp DESC
      LIMIT 10;

  ### Failed Syncs

  Find recent failed syncs:

      SELECT
        connector_id,
        time_stamp,
        message_event,
        message_data
      FROM fivetran_metadata.log
      WHERE event = 'SEVERE'
        OR message_event LIKE '%error%'
        OR message_event LIKE '%fail%'
      ORDER BY time_stamp DESC
      LIMIT 50;

  ### Sync Duration

  Calculate sync duration for recent syncs:

      WITH sync_events AS (
        SELECT
          connector_id,
          time_stamp,
          message_event,
          LAG(time_stamp) OVER (
            PARTITION BY connector_id
            ORDER BY time_stamp
          ) AS prev_time
        FROM fivetran_metadata.log
        WHERE message_event IN ('sync_start', 'sync_end')
      )
      SELECT
        connector_id,
        time_stamp AS sync_end_time,
        DATEDIFF('minute', prev_time, time_stamp) AS duration_minutes
      FROM sync_events
      WHERE message_event = 'sync_end'
        AND connector_id = 'your_connector_id'
      ORDER BY time_stamp DESC
      LIMIT 20;

  ### Schema Changes

  Find schema modification events:

      SELECT
        connector_id,
        time_stamp,
        message_event,
        message_data
      FROM fivetran_metadata.log
      WHERE message_event LIKE '%schema%'
        OR message_event LIKE '%column%'
        OR message_event LIKE '%table%'
      ORDER BY time_stamp DESC
      LIMIT 100;

  ## Usage with Fivetrex

  While Fivetrex cannot query sync logs directly (no REST API exists), you can
  use the connector state and status information:

      # Get current sync state
      {:ok, connector} = Fivetrex.Connectors.get(client, "connector_id")
      Fivetrex.Models.Connector.sync_state(connector)

      # Get sync status summary
      {:ok, status} = Fivetrex.Connectors.get_sync_status(client, "connector_id")

  For historical sync logs and detailed event data, query the `fivetran_metadata`
  schema in your data warehouse using the SQL examples above.

  ## See Also

    * `Fivetrex.Connectors` - For real-time connector status
    * `Fivetrex.Models.Connector` - Connector struct with status helpers
    * [Fivetran Platform Connector docs](https://fivetran.com/docs/logs/fivetran-platform)
  """

  @typedoc """
  Query type atoms for common sync log queries.

    * `:recent_syncs` - Query for recent sync events
    * `:failed_syncs` - Query for failed sync events
    * `:sync_duration` - Query for sync timing information
    * `:schema_changes` - Query for schema modification events
  """
  @type query_type :: :recent_syncs | :failed_syncs | :sync_duration | :schema_changes

  @doc """
  Returns an example SQL query for common sync log use cases.

  These queries are templates designed to work with the Fivetran Platform
  Connector's `fivetran_metadata` schema. You will need to substitute the
  placeholder `'your_connector_id'` with an actual connector ID.

  ## Parameters

    * `query_type` - The type of query to return:
      * `:recent_syncs` - Last 10 sync events for a connector
      * `:failed_syncs` - Recent failure events
      * `:sync_duration` - Sync timing and duration information
      * `:schema_changes` - Schema modification events

  ## Returns

  A SQL query string that can be executed against your data warehouse.

  ## Note

  The returned queries use `fivetran_metadata` as the schema name. If your
  Fivetran Platform Connector uses a different schema name, you will need
  to adjust the queries accordingly.

  ## Examples

      iex> sql = Fivetrex.SyncLogs.query_example(:recent_syncs)
      iex> String.contains?(sql, "fivetran_metadata.log")
      true

      # Substitute the connector ID before executing
      sql = Fivetrex.SyncLogs.query_example(:failed_syncs)
      actual_sql = String.replace(sql, "your_connector_id", "my_actual_connector_id")

  """
  @spec query_example(query_type()) :: String.t()
  def query_example(:recent_syncs) do
    """
    SELECT
      time_stamp,
      event,
      message_event,
      message_data
    FROM fivetran_metadata.log
    WHERE connector_id = 'your_connector_id'
    ORDER BY time_stamp DESC
    LIMIT 10;
    """
  end

  def query_example(:failed_syncs) do
    """
    SELECT
      connector_id,
      time_stamp,
      message_event,
      message_data
    FROM fivetran_metadata.log
    WHERE connector_id = 'your_connector_id'
      AND (
        event = 'SEVERE'
        OR message_event LIKE '%error%'
        OR message_event LIKE '%fail%'
      )
    ORDER BY time_stamp DESC
    LIMIT 50;
    """
  end

  def query_example(:sync_duration) do
    """
    WITH sync_events AS (
      SELECT
        connector_id,
        time_stamp,
        message_event,
        LAG(time_stamp) OVER (
          PARTITION BY connector_id
          ORDER BY time_stamp
        ) AS prev_time
      FROM fivetran_metadata.log
      WHERE message_event IN ('sync_start', 'sync_end')
        AND connector_id = 'your_connector_id'
    )
    SELECT
      connector_id,
      time_stamp AS sync_end_time,
      DATEDIFF('minute', prev_time, time_stamp) AS duration_minutes
    FROM sync_events
    WHERE message_event = 'sync_end'
    ORDER BY time_stamp DESC
    LIMIT 20;
    """
  end

  def query_example(:schema_changes) do
    """
    SELECT
      connector_id,
      time_stamp,
      message_event,
      message_data
    FROM fivetran_metadata.log
    WHERE connector_id = 'your_connector_id'
      AND (
        message_event LIKE '%schema%'
        OR message_event LIKE '%column%'
        OR message_event LIKE '%table%'
      )
    ORDER BY time_stamp DESC
    LIMIT 100;
    """
  end
end
