defmodule FivetrexTest do
  use ExUnit.Case

  describe "client/1" do
    test "creates a client" do
      client = Fivetrex.client(api_key: "key", api_secret: "secret")
      assert %Fivetrex.Client{} = client
    end
  end
end
