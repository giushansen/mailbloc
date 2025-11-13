defmodule Mailbloc.DNS.MXResolver do
  @moduledoc """
  DNS MX resolver proxy with per-server rate limiting.

  Acts as a rate-limiting proxy that:
  1. Rotates through 10 DNS servers (round-robin)
  2. Rate limits EACH DNS server independently (100 qps each)
  3. Skips DNS servers that are rate-limited
  4. Falls back to next available server
  5. Total capacity: 1,000 queries/second

  This module does NOT create ETS tables - it's purely a DNS query proxy.
  The :mx_cache ETS table is created by Mailbloc.BlocklistLoader.
  """

  use GenServer
  require Logger

  # DNS servers with explicit ports and names for debugging
  @dns_servers [
    {{8, 8, 8, 8}, 53, "Google Primary"},
    {{8, 8, 4, 4}, 53, "Google Secondary"},
    {{1, 1, 1, 1}, 53, "Cloudflare Primary"},
    {{1, 0, 0, 1}, 53, "Cloudflare Secondary"},
    {{9, 9, 9, 9}, 53, "Quad9 Primary"},
    {{149, 112, 112, 112}, 53, "Quad9 Secondary"},
    {{208, 67, 222, 222}, 53, "OpenDNS Primary"},
    {{208, 67, 220, 220}, 53, "OpenDNS Secondary"},
    {{209, 244, 0, 3}, 53, "Level3 Primary"},
    {{209, 244, 0, 4}, 53, "Level3 Secondary"}
  ]

  # Rate limiting: 100 queries/sec per server = 1000 total qps
  # Conservative limit to prevent bans while allowing high throughput
  @queries_per_second_per_server 100
  @token_refill_interval 1000
  @dns_timeout 2000

  # ============================================================================
  # CLIENT API
  # ============================================================================

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Lookup MX records using round-robin rotation with per-server rate limiting.

  Returns sorted list of MX records by priority, or error if rate limited or failed.
  DNS query is performed outside the GenServer for better concurrency.
  """
  @spec lookup_mx(String.t()) :: {:ok, list()} | {:error, atom()}
  def lookup_mx(domain) do
    case GenServer.call(__MODULE__, {:acquire_server, domain}, 1_000) do
      {:ok, server_index} ->
        perform_lookup(domain, server_index)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # GENSERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(_opts) do
    # Initialize token bucket for each DNS server
    server_tokens =
      @dns_servers
      |> Enum.with_index()
      |> Map.new(fn {_server, idx} -> {idx, @queries_per_second_per_server} end)

    state = %{
      server_tokens: server_tokens,
      max_tokens: @queries_per_second_per_server,
      current_index: 0,
      server_count: length(@dns_servers)
    }

    schedule_token_refill()

    total_capacity = state.server_count * @queries_per_second_per_server

    Logger.info(
      "[MXResolver] Started with #{length(@dns_servers)} DNS servers, " <>
        "#{@queries_per_second_per_server} qps per server (#{total_capacity} total qps)"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:acquire_server, domain}, _from, state) do
    case find_available_server(state) do
      {:ok, server_index, new_state} ->
        # Move to next server for round-robin distribution
        next_index = rem(state.current_index + 1, state.server_count)
        {:reply, {:ok, server_index}, %{new_state | current_index: next_index}}

      {:error, :all_rate_limited} ->
        Logger.warning("[MXResolver] All DNS servers rate-limited for #{domain}")
        {:reply, {:error, :rate_limited}, state}
    end
  end

  @impl true
  def handle_info(:refill_tokens, state) do
    # Refill all servers back to max tokens every second
    refilled =
      state.server_tokens
      |> Map.new(fn {idx, _} -> {idx, state.max_tokens} end)

    schedule_token_refill()
    {:noreply, %{state | server_tokens: refilled}}
  end

  # ============================================================================
  # DNS SERVER SELECTION & RATE LIMITING
  # ============================================================================

  # Try to find an available server starting from current index (round-robin)
  defp find_available_server(state), do: try_servers(state, state.current_index, 0)

  # Tried all servers, all are rate-limited
  defp try_servers(state, _start_index, attempt) when attempt >= state.server_count do
    {:error, :all_rate_limited}
  end

  # Try server at current position in rotation
  defp try_servers(state, start_index, attempt) do
    idx = rem(start_index + attempt, state.server_count)
    tokens = Map.get(state.server_tokens, idx, 0)

    if tokens > 0 do
      # Consume one token from this server
      new_tokens = Map.put(state.server_tokens, idx, tokens - 1)
      {:ok, idx, %{state | server_tokens: new_tokens}}
    else
      # This server is rate-limited, try next one
      try_servers(state, start_index, attempt + 1)
    end
  end

  # ============================================================================
  # DNS LOOKUP (executed outside GenServer for concurrency)
  # ============================================================================

  defp perform_lookup(domain, server_index) do
    {ip, port, name} = Enum.at(@dns_servers, server_index)
    char_domain = String.to_charlist(domain)

    result =
      :inet_res.lookup(
        char_domain,
        :in,
        :mx,
        nameservers: [{ip, port}],
        timeout: @dns_timeout
      )

    case result do
      [] ->
        {:ok, []}

      mx when is_list(mx) ->
        # Sort by priority (lower number = higher priority)
        sorted = Enum.sort_by(mx, fn {priority, _host} -> priority end)

        if Application.get_env(:mailbloc, :env) != :test do
          Logger.debug("[MXResolver] #{domain} → #{name} (#{format_ip(ip)}:#{port})")
        end

        {:ok, sorted}

      _ ->
        Logger.warning("[MXResolver] Unexpected result from #{name}: #{inspect(result)}")
        {:error, :lookup_failed}
    end
  rescue
    e ->
      {_ip, _port, dns_name} = Enum.at(@dns_servers, server_index)

      # Only log errors that aren't expected validation failures
      if not is_validation_error?(e) do
        Logger.error("[MXResolver] Exception on #{dns_name} for #{domain}: #{inspect(e)}")
      end

      {:error, :exception}
  end

  # Check if this is an expected validation error (like invalid domain format)
  defp is_validation_error?(%FunctionClauseError{function: :encode_labels}), do: true
  defp is_validation_error?(_), do: false

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp schedule_token_refill do
    Process.send_after(self(), :refill_tokens, @token_refill_interval)
  end

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
end
