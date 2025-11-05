defmodule Mailbloc.BlocklistLoaderTest do
  use ExUnit.Case, async: false

  setup do
    # Ensure clean state
    cleanup_test_tables()
    create_test_tables()

    on_exit(fn ->
      cleanup_test_tables()
    end)

    :ok
  end

  describe "ETS table stats" do
    test "returns detailed table statistics" do
      load_test_data()
      stats = get_detailed_table_stats()

      assert is_list(stats)
      assert length(stats) > 0

      first_table = hd(stats)
      assert Map.has_key?(first_table, :name)
      assert Map.has_key?(first_table, :size)
      assert Map.has_key?(first_table, :memory_bytes)
      assert Map.has_key?(first_table, :memory_mb)
      assert is_integer(first_table.size)
      assert is_float(first_table.memory_mb)
    end

    test "shows accurate record counts" do
      load_test_data()
      disposable_count = :ets.info(:disposable_email, :size)

      assert disposable_count == 3
    end
  end

  describe "countdown formatting" do
    test "formats seconds correctly" do
      assert format_countdown(45) == "45 seconds"
      assert format_countdown(90) == "1m 30s"
      assert format_countdown(3661) == "1h 1m"
    end

    test "shows time ago for last update" do
      now = DateTime.utc_now()
      five_min_ago = DateTime.add(now, -300, :second)

      assert format_time_ago(nil) == "never"
      assert format_time_ago(five_min_ago) =~ "minutes ago"
    end
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp create_test_tables do
    tables = [
      :criminal_network_ip,
      :malicious_ip,
      :tor_network_ip,
      :recent_attacker_ip,
      :week_attacker_ip,
      :suspicious_ip,
      :vpn_ip,
      :datacenter_ip,
      :reported_ip,
      :old_attacker_ip,
      :disposable_email,
      :privacy_email,
      :mx_cache
    ]

    Enum.each(tables, fn name ->
      # Delete if exists
      if :ets.whereis(name) != :undefined do
        :ets.delete(name)
      end
      # Create fresh
      :ets.new(name, [:set, :public, :named_table, read_concurrency: true])
    end)
  end

  defp cleanup_test_tables do
    tables = [
      :criminal_network_ip,
      :malicious_ip,
      :tor_network_ip,
      :recent_attacker_ip,
      :week_attacker_ip,
      :suspicious_ip,
      :vpn_ip,
      :datacenter_ip,
      :reported_ip,
      :old_attacker_ip,
      :disposable_email,
      :privacy_email,
      :mx_cache
    ]

    Enum.each(tables, fn name ->
      # Check if table exists before trying to delete
      if :ets.whereis(name) != :undefined do
        try do
          :ets.delete(name)
        rescue
          ArgumentError -> :ok  # Table was deleted by another process, that's fine
        end
      end
    end)
  end

  defp load_test_data do
    # Clear first
    :ets.delete_all_objects(:disposable_email)
    :ets.delete_all_objects(:privacy_email)

    # Load test data
    :ets.insert(:disposable_email, {"tempmail.com", true})
    :ets.insert(:disposable_email, {"guerrillamail.com", true})
    :ets.insert(:disposable_email, {"10minutemail.com", true})

    :ets.insert(:privacy_email, {"simplelogin.com", true})
    :ets.insert(:privacy_email, {"anonaddy.com", true})
  end

  defp get_detailed_table_stats do
    tables = [
      :disposable_email,
      :privacy_email,
      :tor_network_ip
    ]

    Enum.map(tables, fn name ->
      case :ets.info(name) do
        :undefined ->
          %{
            name: name,
            size: 0,
            memory_bytes: 0,
            memory_mb: 0.0,
            type: :set
          }

        info when is_list(info) ->
          %{
            name: name,
            size: info[:size],
            memory_bytes: info[:memory] * :erlang.system_info(:wordsize),
            memory_mb: Float.round(info[:memory] * :erlang.system_info(:wordsize) / 1_024 / 1_024, 2),
            type: info[:type]
          }
      end
    end)
  end

  defp format_countdown(seconds) when seconds <= 0, do: "now"
  defp format_countdown(seconds) when seconds < 60, do: "#{seconds} seconds"
  defp format_countdown(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}m #{remaining_seconds}s"
  end
  defp format_countdown(seconds) do
    hours = div(seconds, 3600)
    remaining_minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{remaining_minutes}m"
  end

  defp format_time_ago(nil), do: "never"
  defp format_time_ago(datetime) do
    seconds_ago = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds_ago < 60 -> "#{seconds_ago} seconds ago"
      seconds_ago < 3600 -> "#{div(seconds_ago, 60)} minutes ago"
      seconds_ago < 86400 -> "#{div(seconds_ago, 3600)} hours ago"
      true -> "#{div(seconds_ago, 86400)} days ago"
    end
  end
end
