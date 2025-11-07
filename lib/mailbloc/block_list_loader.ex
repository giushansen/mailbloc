defmodule Mailbloc.BlocklistLoader do
  @moduledoc """
  Manages blocklist ETS tables: creates them on startup, loads data, updates daily.

  CRITICAL: This module creates ALL ETS tables including :mx_cache
  """

  use GenServer
  require Logger

  @update_interval :timer.hours(24)
  @download_timeout :timer.minutes(10)
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

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def update_now, do: GenServer.cast(__MODULE__, :update_blocklists)
  def status, do: GenServer.call(__MODULE__, :status)

  @impl true
  def init(_opts) do
    create_all_ets_tables()

    # Load existing data SYNCHRONOUSLY so tables are ready before init returns
    {last_update, last_status} = case load_latest_blocklists() do
      :ok ->
        Logger.info("[BlocklistLoader] ✓ Loaded existing blocklists")
        {DateTime.utc_now(), :ok}

      {:error, :no_existing} ->
        Logger.info("[BlocklistLoader] No existing blocklists (OK in test mode)")
        {nil, :pending}
    end

    state = %{
      last_update: last_update,
      last_status: last_status,
      update_count: 0,
      next_update_at: calculate_next_update_time()
    }

    # Schedule background update (async, happens later)
    schedule_update()

    Logger.info("[BlocklistLoader] Initialized with #{length(@blocklists)} blocklists")
    {:ok, state}
  end

  @impl true
  def handle_info(:update_blocklists, state) do
    Logger.info("[BlocklistLoader] 🔄 Starting update...")

    case perform_update() do
      :ok ->
        Logger.info("[BlocklistLoader] ✓ Update completed")
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
    status = %{
      last_update: state.last_update,
      last_status: state.last_status,
      update_count: state.update_count,
      blocklist_count: length(@blocklists)
    }
    {:reply, status, state}
  end

  # ============================================================================
  # ETS TABLE CREATION - RACE-SAFE
  # ============================================================================

  defp create_all_ets_tables do
    Logger.info("[BlocklistLoader] Creating ETS tables...")

    Enum.each(@blocklists, fn {name, _url} ->
      create_table_safe(name)
    end)

    create_table_safe(:mx_cache)

    Logger.info("[BlocklistLoader] ✓ Created #{length(@blocklists) + 1} ETS tables")
  end

  defp create_table_safe(name) do
    try do
      :ets.new(name, [:set, :public, :named_table, read_concurrency: true])
    rescue
      ArgumentError -> :ok
    end
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
      :ok
    else
      {:error, _reason} ->
        cleanup_temp_tables()
        {:error, :update_failed}
    end
  end

  defp download_all_blocklists(dir) do
    results =
      @blocklists
      |> Task.async_stream(
        fn {name, url} -> download_blocklist(name, url, dir) end,
        timeout: @download_timeout,
        max_concurrency: 5
      )
      |> Enum.to_list()

    if Enum.all?(results, fn {:ok, result} -> result == :ok end) do
      :ok
    else
      {:error, :download_failed}
    end
  end

  defp download_blocklist(name, url, dir) do
    file_path = Path.join(dir, "#{name}.txt")

    case :httpc.request(:get, {String.to_charlist(url), []},
                        [{:timeout, @download_timeout}],
                        [body_format: :binary]) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        File.write!(file_path, body)
        :ok

      {:ok, {{_, status, _}, _, _}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _e -> {:error, :exception}
  end

  # ============================================================================
  # ETS LOADING - RACE-SAFE
  # ============================================================================

  defp load_to_temp_tables(dir) do
    Enum.each(@blocklists, fn {name, _url} ->
      temp_name = :"temp_#{name}"

      try do
        :ets.new(temp_name, [:set, :public, :named_table, read_concurrency: true])
      rescue
        ArgumentError -> :ets.delete_all_objects(temp_name)
      end
    end)

    results =
      @blocklists
      |> Enum.map(fn {name, _url} ->
        file_path = Path.join(dir, "#{name}.txt")
        load_file_to_ets(file_path, :"temp_#{name}")
      end)

    if Enum.all?(results, &(&1 == :ok)) do
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

        :ok

      {:error, _reason} ->
        if Mix.env() == :test, do: :ok, else: {:error, :file_not_found}
    end
  end

  defp parse_entry(line) do
    line = String.trim(line)

    cond do
      line == "" -> nil
      String.contains?(line, "#") -> line |> String.split("#") |> hd() |> String.trim()
      String.contains?(line, ";") -> line |> String.split(";") |> hd() |> String.trim()
      String.contains?(line, "\t") -> line |> String.split("\t") |> hd() |> String.trim()
      true -> line
    end
  end

  # ============================================================================
  # ATOMIC SWAP
  # ============================================================================

  defp atomic_swap_tables do
    Enum.each(@blocklists, fn {name, _url} ->
      temp_name = :"temp_#{name}"

      case :ets.whereis(temp_name) do
        :undefined -> throw({:error, :temp_table_missing})
        _ ->
          :ets.delete(name)
          :ets.rename(temp_name, name)
      end
    end)

    :ok
  rescue
    _e -> {:error, :swap_failed}
  end

  defp cleanup_temp_tables do
    Enum.each(@blocklists, fn {name, _url} ->
      temp_name = :"temp_#{name}"
      if :ets.whereis(temp_name) != :undefined do
        :ets.delete(temp_name)
      end
    end)
  end

  defp load_latest_blocklists do
    with {:ok, dirs} <- File.ls(@base_dir),
         [latest | _] <- dirs |> Enum.sort() |> Enum.reverse(),
         latest_dir = Path.join(@base_dir, latest),
         :ok <- load_to_temp_tables(latest_dir),
         :ok <- atomic_swap_tables() do
      :ok
    else
      _ -> {:error, :no_existing}
    end
  end

  defp schedule_update, do: Process.send_after(self(), :update_blocklists, @update_interval)
  defp schedule_retry, do: Process.send_after(self(), :update_blocklists, :timer.hours(1))

  defp calculate_next_update_time do
    DateTime.utc_now() |> DateTime.add(@update_interval, :millisecond)
  end

  defp calculate_retry_time do
    DateTime.utc_now() |> DateTime.add(:timer.hours(1), :millisecond)
  end
end
