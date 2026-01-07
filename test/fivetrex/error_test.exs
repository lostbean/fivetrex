defmodule Fivetrex.ErrorTest do
  use ExUnit.Case, async: true

  alias Fivetrex.Error

  describe "unauthorized/1" do
    test "creates an unauthorized error with correct fields" do
      error = Error.unauthorized("Invalid API key")

      assert %Error{} = error
      assert error.type == :unauthorized
      assert error.message == "Invalid API key"
      assert error.status == 401
      assert error.retry_after == nil
    end

    test "creates an unauthorized error with empty message" do
      error = Error.unauthorized("")

      assert error.type == :unauthorized
      assert error.message == ""
      assert error.status == 401
    end
  end

  describe "not_found/1" do
    test "creates a not_found error with correct fields" do
      error = Error.not_found("Resource not found")

      assert %Error{} = error
      assert error.type == :not_found
      assert error.message == "Resource not found"
      assert error.status == 404
      assert error.retry_after == nil
    end

    test "creates a not_found error with specific resource message" do
      error = Error.not_found("Connector 'abc123' does not exist")

      assert error.type == :not_found
      assert error.message == "Connector 'abc123' does not exist"
    end
  end

  describe "rate_limited/2" do
    test "creates a rate_limited error with retry_after" do
      error = Error.rate_limited("Too many requests", 60)

      assert %Error{} = error
      assert error.type == :rate_limited
      assert error.message == "Too many requests"
      assert error.status == 429
      assert error.retry_after == 60
    end

    test "creates a rate_limited error with nil retry_after" do
      error = Error.rate_limited("Rate limit exceeded", nil)

      assert error.type == :rate_limited
      assert error.status == 429
      assert error.retry_after == nil
    end

    test "creates a rate_limited error with zero retry_after" do
      error = Error.rate_limited("Rate limited", 0)

      assert error.retry_after == 0
    end

    test "creates a rate_limited error with large retry_after" do
      error = Error.rate_limited("Rate limited", 3600)

      assert error.retry_after == 3600
    end
  end

  describe "server_error/2" do
    test "creates a server_error with status 500" do
      error = Error.server_error("Internal server error", 500)

      assert %Error{} = error
      assert error.type == :server_error
      assert error.message == "Internal server error"
      assert error.status == 500
      assert error.retry_after == nil
    end

    test "creates a server_error with status 502" do
      error = Error.server_error("Bad gateway", 502)

      assert error.type == :server_error
      assert error.status == 502
    end

    test "creates a server_error with status 503" do
      error = Error.server_error("Service unavailable", 503)

      assert error.type == :server_error
      assert error.status == 503
    end

    test "creates a server_error with status 504" do
      error = Error.server_error("Gateway timeout", 504)

      assert error.type == :server_error
      assert error.status == 504
    end
  end

  describe "unknown/2" do
    test "creates an unknown error with status" do
      error = Error.unknown("Unexpected error", 418)

      assert %Error{} = error
      assert error.type == :unknown
      assert error.message == "Unexpected error"
      assert error.status == 418
      assert error.retry_after == nil
    end

    test "creates an unknown error with nil status" do
      error = Error.unknown("Connection failed", nil)

      assert error.type == :unknown
      assert error.message == "Connection failed"
      assert error.status == nil
    end

    test "creates an unknown error for edge case status codes" do
      error = Error.unknown("Redirect", 301)

      assert error.type == :unknown
      assert error.status == 301
    end
  end

  describe "Exception behaviour" do
    test "message/1 returns the error message" do
      error = Error.not_found("Resource not found")

      assert Exception.message(error) == "Resource not found"
    end

    test "message/1 works with empty message" do
      error = Error.unauthorized("")

      assert Exception.message(error) == ""
    end

    test "can be raised" do
      error = Error.unauthorized("Invalid credentials")

      assert_raise Error, "Invalid credentials", fn ->
        raise error
      end
    end

    test "can be raised and caught with pattern matching" do
      error = Error.rate_limited("Too many requests", 30)

      try do
        raise error
      rescue
        e in Error ->
          assert e.type == :rate_limited
          assert e.retry_after == 30
      end
    end

    test "can be pattern matched in rescue" do
      error = Error.not_found("Missing resource")

      result =
        try do
          raise error
        rescue
          e in Error ->
            {:not_found, e.message}
        end

      assert result == {:not_found, "Missing resource"}
    end
  end

  describe "struct fields" do
    test "all error types have consistent struct shape" do
      errors = [
        Error.unauthorized("msg1"),
        Error.not_found("msg2"),
        Error.rate_limited("msg3", 10),
        Error.server_error("msg4", 500),
        Error.unknown("msg5", nil)
      ]

      for error <- errors do
        assert Map.has_key?(error, :type)
        assert Map.has_key?(error, :message)
        assert Map.has_key?(error, :status)
        assert Map.has_key?(error, :retry_after)
      end
    end

    test "error type is one of the defined atoms" do
      valid_types = [:unauthorized, :not_found, :rate_limited, :server_error, :unknown]

      errors = [
        Error.unauthorized(""),
        Error.not_found(""),
        Error.rate_limited("", nil),
        Error.server_error("", 500),
        Error.unknown("", nil)
      ]

      for error <- errors do
        assert error.type in valid_types
      end
    end
  end

  describe "pattern matching" do
    test "can pattern match on each error type" do
      # Test each error type matches its corresponding pattern
      assert match?(%Error{type: :unauthorized}, Error.unauthorized("msg"))
      assert match?(%Error{type: :not_found}, Error.not_found("msg"))
      assert match?(%Error{type: :rate_limited}, Error.rate_limited("msg", 60))
      assert match?(%Error{type: :server_error}, Error.server_error("msg", 500))
      assert match?(%Error{type: :unknown}, Error.unknown("msg", nil))
    end

    test "can extract retry_after from rate_limited error" do
      error = Error.rate_limited("Rate limited", 60)

      %Error{type: :rate_limited, retry_after: seconds} = error

      assert seconds == 60
    end

    test "can use error in tuple pattern matching" do
      # Verify tuple with error can be pattern matched
      error = Error.not_found("Not found")
      result = {:error, error}

      assert {:error, %Error{type: :not_found}} = result
      assert {:error, %Error{message: "Not found"}} = result
    end
  end
end
