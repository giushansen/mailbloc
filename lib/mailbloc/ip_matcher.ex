defmodule Mailbloc.IPMatcher do
  @moduledoc """
  Ultra-fast IP matching against ETS tables containing both exact IPs and CIDR ranges.

  Performance: O(1) for exact matches, O(n) for CIDR ranges (but n is small and cached)
  """

  use GenServer
  require Logger

  # Cache CIDR ranges per table for performance
  @cache_refresh_interval :timer.minutes(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if IP matches any entry in table (handles exact IPs and CIDR ranges)
  """
  def matches?(table, ip_string) when is_binary(ip_string) do
    # Validate IP format first
    case parse_ip(ip_string) do
      {:ok, ip_tuple} ->
        # Try exact match first (O(1) - fastest path)
        case :ets.lookup(table, ip_string) do
          [{^ip_string, true}] ->
            true

          [] ->
            # Check CIDR ranges (uses cached ranges for speed)
            check_cidr_ranges(table, ip_tuple, ip_string)
        end

      :error ->
        Logger.warning("[IPMatcher] Invalid IP format: #{ip_string}")
        false
    end
  end

  def matches?(_table, _invalid), do: false

  # ============================================================================
  # GENSERVER (Caches CIDR ranges for performance)
  # ============================================================================

  @impl true
  def init(_opts) do
    # Schedule periodic cache refresh
    schedule_cache_refresh()

    state = %{
      cidr_cache: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_info(:refresh_cache, state) do
    # Refresh CIDR cache
    schedule_cache_refresh()
    {:noreply, state}
  end

  @impl true
  def handle_call({:get_cidr_ranges, table}, _from, state) do
    ranges = get_or_build_cidr_cache(table, state)
    {:reply, ranges, state}
  end

  defp schedule_cache_refresh do
    Process.send_after(self(), :refresh_cache, @cache_refresh_interval)
  end

  defp get_or_build_cidr_cache(table, _state) do
    # Build CIDR cache from ETS table
    if :ets.whereis(table) != :undefined do
      :ets.tab2list(table)
      |> Enum.filter(fn {key, _} ->
        String.contains?(to_string(key), "/")
      end)
      |> Enum.map(fn {cidr_string, _} ->
        parse_cidr(to_string(cidr_string))
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  # ============================================================================
  # CIDR MATCHING
  # ============================================================================

  defp check_cidr_ranges(table, ip_tuple, ip_string) do
    # Get all CIDR ranges from table
    if :ets.whereis(table) != :undefined do
      :ets.tab2list(table)
      |> Enum.any?(fn {key, _} ->
        key_str = to_string(key)

        # Only check entries with "/" (CIDR notation)
        if String.contains?(key_str, "/") do
          ip_in_cidr?(ip_tuple, key_str)
        else
          # Check if it's the same IP (in case stored differently)
          key_str == ip_string
        end
      end)
    else
      false
    end
  end

  defp parse_cidr(cidr_string) do
    case String.split(cidr_string, "/") do
      [ip_str, prefix_str] ->
        with {:ok, ip_tuple} <- parse_ip(ip_str),
             {prefix_len, ""} <- Integer.parse(prefix_str),
             true <- prefix_len >= 0 and prefix_len <= 32 do
          {ip_tuple, prefix_len}
        else
          _ -> nil
        end

      _ -> nil
    end
  end

  defp ip_in_cidr?(ip_tuple, cidr_string) do
    case parse_cidr(cidr_string) do
      {cidr_ip_tuple, prefix_len} ->
        # Convert IPs to integers and apply netmask
        ip_int = ip_to_int(ip_tuple)
        cidr_int = ip_to_int(cidr_ip_tuple)
        mask = cidr_mask(prefix_len)

        # Check if IP is in range
        Bitwise.band(ip_int, mask) == Bitwise.band(cidr_int, mask)

      nil ->
        false
    end
  end

  defp parse_ip(ip_string) when is_binary(ip_string) do
    # Validate format first
    case String.split(ip_string, ".") do
      [a, b, c, d] ->
        with {a_int, ""} <- Integer.parse(a),
             {b_int, ""} <- Integer.parse(b),
             {c_int, ""} <- Integer.parse(c),
             {d_int, ""} <- Integer.parse(d),
             true <- a_int >= 0 and a_int <= 255,
             true <- b_int >= 0 and b_int <= 255,
             true <- c_int >= 0 and c_int <= 255,
             true <- d_int >= 0 and d_int <= 255 do
          {:ok, {a_int, b_int, c_int, d_int}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_ip(_), do: :error

  defp ip_to_int({a, b, c, d}) do
    Bitwise.bsl(a, 24) + Bitwise.bsl(b, 16) + Bitwise.bsl(c, 8) + d
  end

  defp cidr_mask(prefix_len) when prefix_len >= 0 and prefix_len <= 32 do
    if prefix_len == 0 do
      0
    else
      Bitwise.bsl(0xFFFFFFFF, 32 - prefix_len)
    end
  end
end
