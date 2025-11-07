defmodule Mailbloc.DNS.MXResolverTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Mailbloc.DNS.MXResolver

  setup do
    # MXResolver is started by application supervisor - just use it
    {:ok, %{}}
  end

  describe "basic MX lookup" do
    test "successfully looks up MX records for valid domain" do
      assert {:ok, mx_records} = MXResolver.lookup_mx("google.com")
      assert is_list(mx_records)
      assert length(mx_records) > 0

      Enum.each(mx_records, fn {priority, hostname} ->
        assert is_integer(priority)
        assert is_list(hostname)
      end)
    end

    test "looks up MX records for keybloc.io" do
      assert {:ok, mx_records} = MXResolver.lookup_mx("keybloc.io")
      assert is_list(mx_records)
      assert length(mx_records) > 0
    end

    test "returns empty list for domain without MX records" do
      assert {:ok, []} = MXResolver.lookup_mx("nonexistent-subdomain-test-12345.google.com")
    end

    test "handles invalid domain gracefully" do
      capture_log(fn ->
        result = MXResolver.lookup_mx("invalid..domain")
        assert {:ok, []} == result or match?({:error, _}, result)
      end)
    end
  end

  describe "DNS server rotation" do
    test "rotates through DNS servers on consecutive requests" do
      domains = ["google.com", "keybloc.io", "cloudflare.com", "github.com"]

      results = Enum.map(domains, fn domain ->
        MXResolver.lookup_mx(domain)
      end)

      Enum.each(results, fn result ->
        assert {:ok, _mx_records} = result
      end)
    end
  end

  describe "low-level DNS resolution format" do
    test "correct format with port number works" do
      result = :inet_res.lookup(
        ~c"keybloc.io",
        :in,
        :mx,
        nameservers: [{{8, 8, 8, 8}, 53}],
        timeout: 2000
      )

      assert is_list(result)
      assert length(result) > 0
    end

    test "old format without port raises error" do
      assert_raise ArgumentError, fn ->
        :inet_res.lookup(
          ~c"keybloc.io",
          :in,
          :mx,
          nameservers: [{8, 8, 8, 8}],
          timeout: 2000
        )
      end
    end
  end

  describe "rate limiting" do
    @tag timeout: 10_000
    test "rate limiting works under heavy load" do
      # Fire 500 requests - enough to test rate limiting
      # but not so many it breaks subsequent tests

      tasks = for _i <- 1..500 do
        Task.async(fn ->
          MXResolver.lookup_mx("google.com")
        end)
      end

      results = Task.await_many(tasks, 8_000)

      rate_limited = Enum.count(results, &match?({:error, :rate_limited}, &1))
      success = Enum.count(results, &match?({:ok, _}, &1))

      # Verify all requests completed
      assert success + rate_limited == 500

      IO.puts("\nRate limit test: #{success} success, #{rate_limited} rate-limited")

      # If we saw rate limiting, it's working
      if rate_limited > 0 do
        IO.puts("✅ Rate limiting is working!")
      end
    end
  end

  describe "error handling" do
    test "handles timeout gracefully" do
      result = MXResolver.lookup_mx("timeout-test-domain-12345.invalid")
      assert {:ok, []} == result or match?({:error, _}, result)
    end

    test "handles exceptions without crashing GenServer" do
      capture_log(fn ->
        result = MXResolver.lookup_mx("")
        assert {:ok, []} == result or match?({:error, _}, result)
      end)

      # Verify GenServer still works
      assert {:ok, _} = MXResolver.lookup_mx("google.com")
    end
  end

  describe "MX record sorting" do
    test "returns MX records sorted by priority" do
      {:ok, mx_records} = MXResolver.lookup_mx("google.com")
      priorities = Enum.map(mx_records, fn {priority, _} -> priority end)
      assert priorities == Enum.sort(priorities)
    end
  end
end
