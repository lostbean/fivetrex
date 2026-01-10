defmodule Fivetrex.Webhooks do
  @moduledoc """
  Functions for managing Fivetran Webhooks.

  Webhooks provide real-time notifications about Fivetran events such as sync
  starts, completions, and failures. This module supports creating, managing,
  and testing webhooks at both account and group levels.

  ## Overview

  Webhooks can be configured at two levels:

    * **Account-level** - Receives events for all connectors in your account
    * **Group-level** - Receives events only for connectors in a specific group

  ## Common Operations

  ### Listing Webhooks

      {:ok, %{items: webhooks, next_cursor: cursor}} = Fivetrex.Webhooks.list(client)

  ### Getting a Webhook

      {:ok, webhook} = Fivetrex.Webhooks.get(client, "webhook_id")

  ### Creating an Account Webhook

      {:ok, webhook} = Fivetrex.Webhooks.create_account(client, %{
        url: "https://example.com/webhook",
        events: ["sync_start", "sync_end"],
        active: true,
        secret: "my_webhook_secret"
      })

  ### Creating a Group Webhook

      {:ok, webhook} = Fivetrex.Webhooks.create_group(client, "group_id", %{
        url: "https://example.com/webhook",
        events: ["sync_end"],
        active: true
      })

  ### Testing a Webhook

      {:ok, result} = Fivetrex.Webhooks.test(client, "webhook_id")

  ## Streaming

  For iterating over all webhooks without loading them into memory:

      client
      |> Fivetrex.Webhooks.stream()
      |> Stream.filter(&Webhook.account_level?/1)
      |> Enum.each(&IO.inspect/1)

  ## Security

  When creating webhooks with a secret, Fivetran signs each payload using
  HMAC-SHA256. Use `Fivetrex.WebhookSignature.verify/3` to validate incoming
  requests in your webhook handler.

  ## See Also

    * `Fivetrex.Models.Webhook` - The Webhook struct
    * `Fivetrex.Models.WebhookEvent` - Struct for incoming webhook payloads
    * `Fivetrex.WebhookSignature` - Signature verification for incoming webhooks
    * `Fivetrex.WebhookPlug` - Plug for Phoenix/Bandit webhook handling
  """

  alias Fivetrex.Client
  alias Fivetrex.Models.Webhook

  @doc """
  Lists all webhooks (both account and group level).

  Returns a paginated list of webhooks. Use the `next_cursor` from the response
  to fetch the next page, or use `stream/2` for automatic pagination.

  ## Options

    * `:cursor` - Pagination cursor from a previous response's `next_cursor`.
      Pass `nil` or omit for the first page.

    * `:limit` - Maximum number of webhooks to return per page. Maximum is 1000.

  ## Returns

    * `{:ok, %{items: [Webhook.t()], next_cursor: String.t() | nil}}` - A map containing:
      * `:items` - List of `%Fivetrex.Models.Webhook{}` structs
      * `:next_cursor` - Cursor for the next page, or `nil` if this is the last page

    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

  Fetch the first page:

      {:ok, %{items: webhooks, next_cursor: cursor}} = Fivetrex.Webhooks.list(client)

  Fetch the next page using a cursor:

      {:ok, %{items: more_webhooks, next_cursor: next}} =
        Fivetrex.Webhooks.list(client, cursor: cursor)

  """
  @spec list(Client.t(), keyword()) ::
          {:ok, %{items: [Webhook.t()], next_cursor: String.t() | nil}}
          | {:error, Fivetrex.Error.t()}
  def list(client, opts \\ []) do
    params = build_pagination_params(opts)

    case Client.get(client, "/webhooks", params: params) do
      {:ok, %{"data" => %{"items" => items, "next_cursor" => next_cursor}}} ->
        webhooks = Enum.map(items, &Webhook.from_map/1)
        {:ok, %{items: webhooks, next_cursor: next_cursor}}

      {:ok, %{"data" => %{"items" => items}}} ->
        webhooks = Enum.map(items, &Webhook.from_map/1)
        {:ok, %{items: webhooks, next_cursor: nil}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Returns a stream of all webhooks, handling pagination automatically.

  This function returns an Elixir `Stream` that lazily fetches pages as needed.
  It's memory-efficient for iterating over large numbers of webhooks.

  ## Options

    * `:limit` - Number of items per page (passed to each API call)

  ## Returns

  An `Enumerable.t()` that yields `%Fivetrex.Models.Webhook{}` structs.

  ## Examples

  Stream all webhooks:

      Fivetrex.Webhooks.stream(client)
      |> Enum.each(fn webhook ->
        IO.puts("Webhook: \#{webhook.id} -> \#{webhook.url}")
      end)

  Filter by type:

      account_webhooks =
        Fivetrex.Webhooks.stream(client)
        |> Stream.filter(&Webhook.account_level?/1)
        |> Enum.to_list()

  ## Error Handling

  If an API error occurs during streaming, a `Fivetrex.Error` is raised.
  Use `try/rescue` to handle errors:

      try do
        Fivetrex.Webhooks.stream(client) |> Enum.to_list()
      rescue
        e in Fivetrex.Error ->
          Logger.error("Failed: \#{e.message}")
          []
      end

  """
  @spec stream(Client.t(), keyword()) :: Enumerable.t()
  def stream(client, opts \\ []) do
    Fivetrex.Stream.paginate(fn cursor ->
      list(client, Keyword.put(opts, :cursor, cursor))
    end)
  end

  @doc """
  Gets a webhook by its ID.

  ## Parameters

    * `client` - The Fivetrex client
    * `webhook_id` - The unique identifier of the webhook

  ## Returns

    * `{:ok, Webhook.t()}` - The webhook as a `%Fivetrex.Models.Webhook{}` struct
    * `{:error, Fivetrex.Error.t()}` - On failure (e.g., `:not_found` if ID is invalid)

  ## Examples

      {:ok, webhook} = Fivetrex.Webhooks.get(client, "webhook_id")
      IO.puts("Webhook URL: \#{webhook.url}")

  Handle not found:

      case Fivetrex.Webhooks.get(client, "invalid_id") do
        {:ok, webhook} -> webhook
        {:error, %Fivetrex.Error{type: :not_found}} -> nil
      end

  """
  @spec get(Client.t(), String.t()) :: {:ok, Webhook.t()} | {:error, Fivetrex.Error.t()}
  def get(client, webhook_id) do
    case Client.get(client, "/webhooks/#{webhook_id}") do
      {:ok, %{"data" => data}} ->
        {:ok, Webhook.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Creates an account-level webhook.

  Account webhooks receive events for all connectors in your Fivetran account.

  ## Parameters

    * `client` - The Fivetrex client
    * `params` - A map with webhook parameters:
      * `:url` - Required. Endpoint URL for webhook delivery.
      * `:events` - Required. List of event types (e.g., `["sync_start", "sync_end"]`).
      * `:active` - Optional. Whether webhook is active (default: true).
      * `:secret` - Optional. Secret for HMAC signature verification.

  ## Returns

    * `{:ok, Webhook.t()}` - The created webhook
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, webhook} = Fivetrex.Webhooks.create_account(client, %{
        url: "https://example.com/fivetran/webhook",
        events: ["sync_end"],
        active: true,
        secret: "my_secret_key"
      })
      IO.puts("Created webhook: \#{webhook.id}")

  """
  @spec create_account(Client.t(), map()) :: {:ok, Webhook.t()} | {:error, Fivetrex.Error.t()}
  def create_account(client, params) do
    case Client.post(client, "/webhooks/account", params) do
      {:ok, %{"data" => data}} ->
        {:ok, Webhook.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Creates a group-level webhook.

  Group webhooks receive events only for connectors in the specified group.

  ## Parameters

    * `client` - The Fivetrex client
    * `group_id` - The ID of the group to attach the webhook to
    * `params` - A map with webhook parameters (same as `create_account/2`):
      * `:url` - Required. Endpoint URL for webhook delivery.
      * `:events` - Required. List of event types.
      * `:active` - Optional. Whether webhook is active (default: true).
      * `:secret` - Optional. Secret for HMAC signature verification.

  ## Returns

    * `{:ok, Webhook.t()}` - The created webhook
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, webhook} = Fivetrex.Webhooks.create_group(client, "group_id", %{
        url: "https://example.com/fivetran/webhook",
        events: ["sync_start", "sync_end"],
        active: true
      })
      IO.puts("Created group webhook: \#{webhook.id}")

  """
  @spec create_group(Client.t(), String.t(), map()) ::
          {:ok, Webhook.t()} | {:error, Fivetrex.Error.t()}
  def create_group(client, group_id, params) do
    case Client.post(client, "/webhooks/group/#{group_id}", params) do
      {:ok, %{"data" => data}} ->
        {:ok, Webhook.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Updates an existing webhook.

  ## Parameters

    * `client` - The Fivetrex client
    * `webhook_id` - The ID of the webhook to update
    * `params` - A map with fields to update:
      * `:url` - New endpoint URL
      * `:events` - Updated list of event types
      * `:active` - Enable/disable the webhook
      * `:secret` - New secret for signature verification

  ## Returns

    * `{:ok, Webhook.t()}` - The updated webhook
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      {:ok, webhook} = Fivetrex.Webhooks.update(client, "webhook_id", %{
        active: false
      })

      {:ok, webhook} = Fivetrex.Webhooks.update(client, "webhook_id", %{
        events: ["sync_end", "sync_start"],
        url: "https://new-url.example.com/webhook"
      })

  """
  @spec update(Client.t(), String.t(), map()) ::
          {:ok, Webhook.t()} | {:error, Fivetrex.Error.t()}
  def update(client, webhook_id, params) do
    case Client.patch(client, "/webhooks/#{webhook_id}", params) do
      {:ok, %{"data" => data}} ->
        {:ok, Webhook.from_map(data)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Deletes a webhook.

  **Warning:** This operation cannot be undone. The webhook will immediately
  stop receiving events.

  ## Parameters

    * `client` - The Fivetrex client
    * `webhook_id` - The ID of the webhook to delete

  ## Returns

    * `:ok` - On successful deletion
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

      :ok = Fivetrex.Webhooks.delete(client, "webhook_id")

  """
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Fivetrex.Error.t()}
  def delete(client, webhook_id) do
    case Client.delete(client, "/webhooks/#{webhook_id}") do
      {:ok, _} ->
        :ok

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Sends a test event to a webhook.

  Fivetran sends a test webhook with a dummy connection identifier `_connection_1`.
  Use this to verify your webhook endpoint is correctly configured and can
  receive events.

  ## Parameters

    * `client` - The Fivetrex client
    * `webhook_id` - The ID of the webhook to test
    * `opts` - Optional keyword list:
      * `:event` - Specific event type to test (e.g., `"sync_end"`)

  ## Returns

    * `{:ok, map()}` - Test result from Fivetran
    * `{:error, Fivetrex.Error.t()}` - On failure

  ## Examples

  Send a default test event:

      {:ok, result} = Fivetrex.Webhooks.test(client, "webhook_id")

  Test a specific event type:

      {:ok, result} = Fivetrex.Webhooks.test(client, "webhook_id", event: "sync_end")

  """
  @spec test(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Fivetrex.Error.t()}
  def test(client, webhook_id, opts \\ []) do
    body = if event = opts[:event], do: %{event: event}, else: %{}

    case Client.post(client, "/webhooks/#{webhook_id}/test", body) do
      {:ok, %{"data" => data}} ->
        {:ok, data}

      {:ok, response} ->
        {:ok, response}

      {:error, _} = error ->
        error
    end
  end

  defp build_pagination_params(opts) do
    []
    |> maybe_add_param(:cursor, opts[:cursor])
    |> maybe_add_param(:limit, opts[:limit])
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: [{key, value} | params]
end
