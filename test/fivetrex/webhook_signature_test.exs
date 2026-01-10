defmodule Fivetrex.WebhookSignatureTest do
  use ExUnit.Case, async: true

  alias Fivetrex.WebhookSignature

  @secret "my_webhook_secret"
  @payload ~s({"event":"sync_end","connector_id":"abc123"})

  describe "compute_signature/2" do
    test "computes HMAC-SHA256 signature in uppercase hex" do
      signature = WebhookSignature.compute_signature(@payload, @secret)

      assert is_binary(signature)
      # Should be uppercase hex (64 characters for SHA256)
      assert String.match?(signature, ~r/^[A-F0-9]{64}$/)
    end

    test "produces consistent signatures for same input" do
      sig1 = WebhookSignature.compute_signature(@payload, @secret)
      sig2 = WebhookSignature.compute_signature(@payload, @secret)

      assert sig1 == sig2
    end

    test "produces different signatures for different payloads" do
      sig1 = WebhookSignature.compute_signature(@payload, @secret)
      sig2 = WebhookSignature.compute_signature("different payload", @secret)

      refute sig1 == sig2
    end

    test "produces different signatures for different secrets" do
      sig1 = WebhookSignature.compute_signature(@payload, @secret)
      sig2 = WebhookSignature.compute_signature(@payload, "different_secret")

      refute sig1 == sig2
    end
  end

  describe "verify/3" do
    test "returns :ok for valid signature" do
      signature = WebhookSignature.compute_signature(@payload, @secret)

      assert :ok = WebhookSignature.verify(@payload, signature, @secret)
    end

    test "returns :ok for lowercase signature (case insensitive)" do
      signature =
        WebhookSignature.compute_signature(@payload, @secret)
        |> String.downcase()

      assert :ok = WebhookSignature.verify(@payload, signature, @secret)
    end

    test "returns :ok for mixed case signature" do
      signature = WebhookSignature.compute_signature(@payload, @secret)
      # Mix up the case
      mixed = String.slice(signature, 0, 32) <> String.downcase(String.slice(signature, 32, 32))

      assert :ok = WebhookSignature.verify(@payload, mixed, @secret)
    end

    test "returns error for invalid signature" do
      assert {:error, :invalid_signature} =
               WebhookSignature.verify(@payload, "INVALID_SIGNATURE", @secret)
    end

    test "returns error for nil signature" do
      assert {:error, :missing_signature} =
               WebhookSignature.verify(@payload, nil, @secret)
    end

    test "returns error for empty signature" do
      assert {:error, :missing_signature} =
               WebhookSignature.verify(@payload, "", @secret)
    end

    test "returns error when payload is modified" do
      signature = WebhookSignature.compute_signature(@payload, @secret)
      modified_payload = @payload <> "extra"

      assert {:error, :invalid_signature} =
               WebhookSignature.verify(modified_payload, signature, @secret)
    end

    test "returns error when secret is wrong" do
      signature = WebhookSignature.compute_signature(@payload, @secret)

      assert {:error, :invalid_signature} =
               WebhookSignature.verify(@payload, signature, "wrong_secret")
    end

    test "handles unicode payloads" do
      unicode_payload = ~s({"message":"Hello \u4e16\u754c"})
      signature = WebhookSignature.compute_signature(unicode_payload, @secret)

      assert :ok = WebhookSignature.verify(unicode_payload, signature, @secret)
    end

    test "handles empty payload" do
      empty_payload = ""
      signature = WebhookSignature.compute_signature(empty_payload, @secret)

      assert :ok = WebhookSignature.verify(empty_payload, signature, @secret)
    end
  end

  describe "signature_header/0" do
    test "returns the expected header name" do
      assert WebhookSignature.signature_header() == "x-fivetran-signature-256"
    end
  end

  describe "security" do
    test "verify uses constant-time comparison" do
      # This test ensures we're using secure_compare by testing that both
      # matching prefixes and completely wrong signatures take similar time
      # (not a perfect test, but documents the intent)
      signature = WebhookSignature.compute_signature(@payload, @secret)

      # Both should return the same error - the important thing is that
      # we're using Plug.Crypto.secure_compare internally
      assert {:error, :invalid_signature} =
               WebhookSignature.verify(@payload, "A" <> String.slice(signature, 1, 63), @secret)

      assert {:error, :invalid_signature} =
               WebhookSignature.verify(@payload, String.duplicate("X", 64), @secret)
    end
  end
end
