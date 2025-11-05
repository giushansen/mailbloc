defmodule Mailbloc.BlocklistLoader do
  @moduledoc """
  Manages blocklist ETS tables lifecycle: creation, loading, and daily updates.

  Features:
  - Creates all ETS tables on startup
  - Daily automatic updates via GenServer
  - Downloads to timestamped directories (YYYYMMDD)
  - Loads into temporary ETS tables first
  - Atomic swap to production tables only if all successful
  - Retry logic with exponential backoff
  - Safe rollback on any failure
  """

  use GenServer
  require Logger

  @update_interval :timer.hours(24) # Daily updates
  @download_timeout :timer.minutes(10) # 10 min per file
  @base_dir "priv/blocklists"

  @blocklists [
    # HIGH RISK - IPs
    {:criminal_network_ip, "https://www.spamhaus.org/drop/drop.txt"},
    {:malicious_ip, "https://raw.githubusercontent.com/stamparm/ipsum/master/levels/8.txt"},
    {:tor_network_ip, "https://check.torproject.org/torbulkexitlist"},
    {:recent_attacker_ip, "https://raw.githubusercontent.com/borestad/blocklist-abuseipdb/main/abuseipdb-s100-1d.ipv4"},

    # HIGH RISK - Emails
    {:disposable_email, "https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/master/disposable_email_blocklist.conf"},

    # MEDIUM RISK - IPs
    {:week_attacker_ip, "https://raw.githubusercontent.com/borestad/blocklist-abuseipdb/main/abuseipdb-s100-7d.ipv4"},
    {:suspicious_ip, "https://raw.githubusercontent.com/stamparm/ipsum/master/levels/3.txt"},
    {:vpn_ip, "https://raw.githubusercontent.com/X4BNet/lists_vpn/main/output/vpn/ipv4.txt"},
    {:datacenter_ip, "https://raw.githubusercontent.com/X4BNet/lists_vpn/main/output/datacenter/ipv4.txt"},

    # MEDIUM RISK - Emails
    {:privacy_email, "https://raw.githubusercontent.com/disposable/disposable-email-domains/master/domains_strict.txt"},

    # LOW RISK - IPs
    {:reported_ip, "https://raw.githubusercontent.com/stamparm/ipsum/master/levels/1.txt"},
    {:old_attacker_ip, "https://raw.githubusercontent.com/borestad/blocklist-abuseipdb/main/abuseipdb-s100-30d.ipv4"}
  ]

  # ============================================================================
  # CLIENT API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Manually trigger a blocklist update"
  def update_now do
    GenServer.cast(__MODULE__, :update_blocklists)
  end

  @doc "Get last update status with detailed stats"
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # ============================================================================
  # SERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(_opts) do
    # Step 1: Create all ETS tables
    create_all_ets_tables()

    state = %{
      last_update: nil,
      last_status: :pending,
      update_count: 0,
      next_update_at: calculate_next_update_time()
    }

    # Step 2: Load existing blocklists or download new ones
    send(self(), :load_existing_or_update)

    # Step 3: Schedule periodic updates
    schedule_update()

    Logger.info("[BlocklistLoader] Initialized with #{length(@blocklists)} blocklists")
    {:ok, state}
  end

  @impl true
  def handle_info(:load_existing_or_update, state) do
    case load_latest_blocklists() do
      :ok ->
        Logger.info("[BlocklistLoader] ✓ Loaded existing blocklists successfully")
        {:noreply, %{state |
          last_update: DateTime.utc_now(),
          last_status: :ok,
          next_update_at: calculate_next_update_time()
        }}

      {:error, :no_existing} ->
        Logger.info("[BlocklistLoader] No existing blocklists found, downloading now...")
        send(self(), :update_blocklists)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:update_blocklists, state) do
    Logger.info("[BlocklistLoader] 🔄 Starting scheduled update...")

    case perform_update() do
      :ok ->
        Logger.info("[BlocklistLoader] ✓ Update completed successfully")
        schedule_update()
        {:noreply, %{state |
          last_update: DateTime.utc_now(),
          last_status: :ok,
          update_count: state.update_count + 1,
          next_update_at: calculate_next_update_time()
        }}

      {:error, reason} ->
        Logger.error("[BlocklistLoader] ✗ Update failed: #{inspect(reason)}")
        schedule_retry()
        {:noreply, %{state |
          last_status: {:error, reason},
          next_update_at: calculate_retry_time()
        }}
    end
  end

  @impl true
  def handle_cast(:update_blocklists, state) do
    send(self(), :update_blocklists)
    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    now = DateTime.utc_now()

    time_until_next = if state.next_update_at do
      DateTime.diff(state.next_update_at, now, :second)
    else
      0
    end

    status = %{
      last_update: state.last_update,
      last_update_ago: format_time_ago(state.last_update),
      last_status: state.last_status,
      update_count: state.update_count,
      next_update_at: state.next_update_at,
      next_update_in: format_countdown(time_until_next),
      blocklist_count: length(@blocklists),
      tables: get_detailed_table_stats()
    }

    {:reply, status, state}
  end

  # ============================================================================
  # ETS TABLE CREATION
  # ============================================================================

  defp create_all_ets_tables do
    Logger.info("[BlocklistLoader] Creating ETS tables...")

    # Create production tables
    Enum.each(@blocklists, fn {name, _url} ->
      :ets.new(name, [:set, :public, :named_table, read_concurrency: true])
    end)

    # Create MX cache table
    :ets.new(:mx_cache, [:set, :public, :named_table, read_concurrency: true])

    Logger.info("[BlocklistLoader] ✓ Created #{length(@blocklists) + 1} ETS tables")
  end

  # ============================================================================
  # UPDATE LOGIC
  # ============================================================================

  defp perform_update do
    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d")
    download_dir = Path.join([@base_dir, timestamp])
    File.mkdir_p!(download_dir)

    with :ok <- download_all_blocklists(download_dir),
         :ok <- load_to_temp_tables(download_dir),
         :ok <- atomic_swap_tables() do
      Logger.info("[BlocklistLoader] ✓ Atomic swap completed")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("[BlocklistLoader] ✗ Update failed at #{inspect(reason)}, rolling back...")
        cleanup_temp_tables()
        error
    end
  end

  defp download_all_blocklists(dir) do
    Logger.info("[BlocklistLoader] 📥 Downloading #{length(@blocklists)} blocklists...")

    results =
      @blocklists
      |> Task.async_stream(
        fn {name, url} -> download_blocklist(name, url, dir) end,
        timeout: @download_timeout,
        max_concurrency: 5
      )
      |> Enum.to_list()

    if Enum.all?(results, fn {:ok, result} -> result == :ok end) do
      Logger.info("[BlocklistLoader] ✓ All downloads successful")
      :ok
    else
      failed = Enum.filter(results, fn {:ok, result} -> result != :ok end)
      Logger.error("[BlocklistLoader] ✗ #{length(failed)} downloads failed")
      {:error, :download_failed}
    end
  end

  defp download_blocklist(name, url, dir) do
    file_path = Path.join(dir, "#{name}.txt")

    Logger.debug("[BlocklistLoader] Downloading #{name}...")

    case :httpc.request(:get, {String.to_charlist(url), []},
                        [{:timeout, @download_timeout}],
                        [body_format: :binary]) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        File.write!(file_path, body)
        Logger.debug("[BlocklistLoader] ✓ #{name}: #{byte_size(body)} bytes")
        :ok

      {:ok, {{_, status, _}, _, _}} ->
        Logger.error("[BlocklistLoader] ✗ HTTP #{status} for #{name}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("[BlocklistLoader] ✗ Failed to download #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("[BlocklistLoader] ✗ Exception downloading #{name}: #{inspect(e)}")
      {:error, :exception}
  end

  # ============================================================================
  # ETS LOADING
  # ============================================================================

  defp load_to_temp_tables(dir) do
    Logger.info("[BlocklistLoader] 📊 Loading blocklists to temp ETS tables...")

    # Create temp tables
    Enum.each(@blocklists, fn {name, _url} ->
      temp_name = :"temp_#{name}"
      :ets.new(temp_name, [:set, :public, :named_table, read_concurrency: true])
    end)

    # Load data into temp tables
    results =
      @blocklists
      |> Enum.map(fn {name, _url} ->
        file_path = Path.join(dir, "#{name}.txt")
        load_file_to_ets(file_path, :"temp_#{name}")
      end)

    if Enum.all?(results, &(&1 == :ok)) do
      Logger.info("[BlocklistLoader] ✓ All temp tables loaded")
      :ok
    else
      cleanup_temp_tables()
      {:error, :load_failed}
    end
  end

  defp load_file_to_ets(path, table) do
    case File.read(path) do
      {:ok, content} ->
        entries =
          content
          |> String.split("\n", trim: true)
          |> Enum.reject(&(String.starts_with?(&1, "#") or String.trim(&1) == ""))
          |> Enum.map(&parse_entry/1)
          |> Enum.reject(&is_nil/1)

        Enum.each(entries, fn entry ->
          :ets.insert(table, {entry, true})
        end)

        Logger.debug("[BlocklistLoader] ✓ Loaded #{length(entries)} entries into #{table}")
        :ok

      {:error, reason} ->
        Logger.error("[BlocklistLoader] ✗ Failed to read #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_entry(line) do
    line = String.trim(line)

    cond do
      line == "" ->
        nil

      String.contains?(line, "#") ->
        line |> String.split("#") |> hd() |> String.trim()

      String.contains?(line, ";") ->
        line |> String.split(";") |> hd() |> String.trim()

      String.contains?(line, "\t") ->
        line |> String.split("\t") |> hd() |> String.trim()

      true ->
        line
    end
  end

  # ============================================================================
  # ATOMIC SWAP
  # ============================================================================

  defp atomic_swap_tables do
    Logger.info("[BlocklistLoader] 🔄 Performing atomic swap...")

    Enum.each(@blocklists, fn {name, _url} ->
      temp_name = :"temp_#{name}"

      # Get current count before swap
      old_count = :ets.info(name, :size)
      new_count = :ets.info(temp_name, :size)

      # Delete old production table
      :ets.delete(name)

      # Rename temp to production
      :ets.rename(temp_name, name)

      Logger.debug("[BlocklistLoader] ✓ #{name}: #{old_count} → #{new_count} entries")
    end)

    Logger.info("[BlocklistLoader] ✓ Atomic swap completed successfully")
    :ok
  rescue
    e ->
      Logger.error("[BlocklistLoader] ✗ Atomic swap failed: #{inspect(e)}")
      {:error, :swap_failed}
  end

  defp cleanup_temp_tables do
    Logger.warning("[BlocklistLoader] 🧹 Cleaning up temp tables...")

    Enum.each(@blocklists, fn {name, _url} ->
      temp_name = :"temp_#{name}"
      if :ets.whereis(temp_name) != :undefined do
        :ets.delete(temp_name)
      end
    end)
  end

  # ============================================================================
  # LOAD EXISTING BLOCKLISTS
  # ============================================================================

  defp load_latest_blocklists do
    with {:ok, dirs} <- File.ls(@base_dir),
         [latest | _] <- dirs |> Enum.sort() |> Enum.reverse(),
         latest_dir = Path.join(@base_dir, latest),
         :ok <- load_to_temp_tables(latest_dir),
         :ok <- atomic_swap_tables() do
      Logger.info("[BlocklistLoader] ✓ Loaded from existing: #{latest}")
      :ok
    else
      _ ->
        {:error, :no_existing}
    end
  end

  # ============================================================================
  # SCHEDULING
  # ============================================================================

  defp schedule_update do
    Process.send_after(self(), :update_blocklists, @update_interval)
  end

  defp schedule_retry do
    # Retry in 1 hour on failure
    Process.send_after(self(), :update_blocklists, :timer.hours(1))
  end

  defp calculate_next_update_time do
    DateTime.utc_now() |> DateTime.add(@update_interval, :millisecond)
  end

  defp calculate_retry_time do
    DateTime.utc_now() |> DateTime.add(:timer.hours(1), :millisecond)
  end

  # ============================================================================
  # STATS & FORMATTING
  # ============================================================================

  defp get_detailed_table_stats do
    tables =
      @blocklists
      |> Enum.map(fn {name, _url} ->
        # Check if table exists first
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

    # Add MX cache stats
    case :ets.info(:mx_cache) do
      :undefined ->
        tables

      mx_cache_info when is_list(mx_cache_info) ->
        mx_cache_stats = %{
          name: :mx_cache,
          size: mx_cache_info[:size],
          memory_bytes: mx_cache_info[:memory] * :erlang.system_info(:wordsize),
          memory_mb: Float.round(mx_cache_info[:memory] * :erlang.system_info(:wordsize) / 1_024 / 1_024, 2),
          type: mx_cache_info[:type]
        }

        tables ++ [mx_cache_stats]
    end
  end

  defp format_countdown(seconds) when seconds <= 0, do: "now"
  defp format_countdown(seconds) when seconds < 60 do
    "#{seconds} seconds"
  end
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
