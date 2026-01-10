defmodule Fivetrex.WebhookSignaturePropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Fivetrex.WebhookSignature

  # Test properties:

  # 1. Roundtrip property: compute then verify always succeeds
  property "compute_signature/2 then verify/3 always succeeds" do
    check all(
            payload <- string(:printable),
            secret <- string(:printable, min_length: 1)
          ) do
      signature = WebhookSignature.compute_signature(payload, secret)
      assert :ok = WebhookSignature.verify(payload, signature, secret)
    end
  end

  # 2. Signature determinism: same inputs produce same output
  property "compute_signature/2 is deterministic" do
    check all(
            payload <- string(:printable),
            secret <- string(:printable, min_length: 1)
          ) do
      sig1 = WebhookSignature.compute_signature(payload, secret)
      sig2 = WebhookSignature.compute_signature(payload, secret)
      assert sig1 == sig2
    end
  end

  # 3. Different payloads produce different signatures (with high probability)
  property "different payloads produce different signatures" do
    check all(
            payload1 <- string(:printable, min_length: 1),
            payload2 <- string(:printable, min_length: 1),
            secret <- string(:printable, min_length: 1),
            payload1 != payload2
          ) do
      sig1 = WebhookSignature.compute_signature(payload1, secret)
      sig2 = WebhookSignature.compute_signature(payload2, secret)
      assert sig1 != sig2
    end
  end

  # 4. Different secrets produce different signatures
  property "different secrets produce different signatures" do
    check all(
            payload <- string(:printable, min_length: 1),
            secret1 <- string(:printable, min_length: 1),
            secret2 <- string(:printable, min_length: 1),
            secret1 != secret2
          ) do
      sig1 = WebhookSignature.compute_signature(payload, secret1)
      sig2 = WebhookSignature.compute_signature(payload, secret2)
      assert sig1 != sig2
    end
  end

  # 5. Case insensitivity of verification
  property "verify/3 is case-insensitive for signature" do
    check all(
            payload <- string(:printable),
            secret <- string(:printable, min_length: 1)
          ) do
      signature = WebhookSignature.compute_signature(payload, secret)

      assert :ok = WebhookSignature.verify(payload, signature, secret)
      assert :ok = WebhookSignature.verify(payload, String.downcase(signature), secret)
      assert :ok = WebhookSignature.verify(payload, String.upcase(signature), secret)
    end
  end

  # 6. Binary payloads (including non-printable) work
  property "works with arbitrary binary payloads" do
    check all(
            payload <- binary(),
            secret <- string(:printable, min_length: 1)
          ) do
      signature = WebhookSignature.compute_signature(payload, secret)
      assert :ok = WebhookSignature.verify(payload, signature, secret)
    end
  end
end
