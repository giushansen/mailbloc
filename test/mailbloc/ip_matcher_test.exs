defmodule Mailbloc.IPMatcherTest do
  use ExUnit.Case, async: false

  alias Mailbloc.IPMatcher

  setup do
    # Create test table
    if :ets.whereis(:test_ip) != :undefined do
      :ets.delete(:test_ip)
    end
    :ets.new(:test_ip, [:set, :public, :named_table])

    # Load realistic test data (BOTH formats)
    :ets.insert(:test_ip, {"194.127.167.107/32", true})  # Single IP as CIDR
    :ets.insert(:test_ip, {"192.168.1.0/24", true})      # IP range
    :ets.insert(:test_ip, {"10.0.0.0/8", true})          # Large range
    :ets.insert(:test_ip, {"8.8.8.8", true})             # Exact IP (no mask)

    on_exit(fn ->
      if :ets.whereis(:test_ip) != :undefined do
        :ets.delete(:test_ip)
      end
    end)

    :ok
  end

  describe "exact IP matching" do
    test "matches exact IP without CIDR" do
      assert IPMatcher.matches?(:test_ip, "8.8.8.8")
    end

    test "does not match non-existent exact IP" do
      refute IPMatcher.matches?(:test_ip, "9.9.9.9")
    end
  end

  describe "CIDR range matching" do
    test "matches IP in /32 range (single IP)" do
      assert IPMatcher.matches?(:test_ip, "194.127.167.107")
    end

    test "matches IP in /24 range" do
      assert IPMatcher.matches?(:test_ip, "192.168.1.1")
      assert IPMatcher.matches?(:test_ip, "192.168.1.100")
      assert IPMatcher.matches?(:test_ip, "192.168.1.255")
    end

    test "matches IP in /8 range (large range)" do
      assert IPMatcher.matches?(:test_ip, "10.0.0.1")
      assert IPMatcher.matches?(:test_ip, "10.255.255.255")
    end

    test "does not match IP outside /24 range" do
      refute IPMatcher.matches?(:test_ip, "192.168.2.1")
      refute IPMatcher.matches?(:test_ip, "192.169.1.1")
    end

    test "does not match IP outside /8 range" do
      refute IPMatcher.matches?(:test_ip, "11.0.0.1")
    end
  end

  describe "invalid input handling" do
    test "rejects invalid IP format" do
      refute IPMatcher.matches?(:test_ip, "not-an-ip")
      refute IPMatcher.matches?(:test_ip, "999.999.999.999")
      refute IPMatcher.matches?(:test_ip, "192.168.1")
      refute IPMatcher.matches?(:test_ip, "192.168.1.1.1")
    end

    test "handles non-string input" do
      refute IPMatcher.matches?(:test_ip, nil)
      refute IPMatcher.matches?(:test_ip, 123)
      refute IPMatcher.matches?(:test_ip, %{})
    end
  end

  describe "performance" do
    test "exact match is O(1) fast" do
      {time, result} = :timer.tc(fn ->
        IPMatcher.matches?(:test_ip, "8.8.8.8")
      end)

      assert result == true
      assert time < 1000  # Should be sub-millisecond
    end
  end
end
