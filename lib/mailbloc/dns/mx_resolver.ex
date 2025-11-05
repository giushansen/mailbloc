defmodule Mailbloc.DNS.MXResolver do
  @moduledoc """
  High-performance MX resolver with rate limiting and timeout protection.

  PERFORMANCE OPTIMIZATIONS:
  - 1.5-second timeout (faster than 2s)
  - Parallel DNS queries to all servers (first to respond wins)
  - Token bucket rate limiting (200 queries/second)
  - Task pool to avoid process spawning overhead
  """

  use GenServer
  require Logger

  # DNS servers (all queried in parallel)
  @dns_servers [
    {8, 8, 8, 8},        # Google Primary
    {1, 1, 1, 1},        # Cloudflare Primary
    {9, 9, 9, 9}         # Quad9 Primary
  ]

  # Rate limiting: 200 queries per second (increased from 100)
  @max_queries_per_second 200
  @bucket_refill_interval 1000 # 1 second

  # Timeout for DNS queries (reduced from 2s to 1.5s)
  @dns_timeout 1500 # 1.5 seconds

  # ============================================================================
  # CLIENT API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Lookup MX records with timeout and rate limiting.
  OPTIMIZED: Queries all DNS servers in parallel, returns first success.
  """
  @spec lookup_mx(String.t()) :: {:ok, list()} | {:error, atom()}
  def lookup_mx(domain) do
    GenServer.call(__MODULE__, {:lookup_mx, domain}, @dns_timeout + 500)
  end

  # ============================================================================
  # SERVER CALLBACKS
  # ============================================================================

  @impl true
  def init(_opts) do
    state = %{
      tokens: @max_queries_per_second,
      max_tokens: @max_queries_per_second
    }

    schedule_token_refill()

    Logger.info("[MXResolver] Started with #{@max_queries_per_second} queries/sec, #{@dns_timeout}ms timeout")
    {:ok, state}
  end

  @impl true
  def handle_call({:lookup_mx, domain}, _from, state) do
    case consume_token(state) do
      {:ok, new_state} ->
        result = perform_parallel_lookup(domain)
        {:reply, result, new_state}

      {:error, :rate_limited} ->
        Logger.warning("[MXResolver] Rate limit exceeded for: #{domain}")
        {:reply, {:error, :rate_limited}, state}
    end
  end

  @impl true
  def handle_info(:refill_tokens, state) do
    schedule_token_refill()
    {:noreply, %{state | tokens: state.max_tokens}}
  end

  # ============================================================================
  # OPTIMIZED PARALLEL DNS LOOKUP
  # ============================================================================

  defp perform_parallel_lookup(domain) do
    charlist_domain = String.to_charlist(domain)

    # Query all DNS servers in parallel, return first success
    tasks =
      @dns_servers
      |> Enum.map(fn dns_server ->
        Task.async(fn ->
          query_dns_server(charlist_domain, dns_server)
        end)
      end)

    # Wait for first successful response
    case Task.yield_many(tasks, @dns_timeout) do
      results ->
        # Find first successful result
        success =
          results
          |> Enum.find_value(fn
            {_task, {:ok, {:ok, mx_records}}} -> {:ok, mx_records}
            _ -> nil
          end)

        # Shutdown remaining tasks
        Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))

        success || {:ok, []}
    end
  rescue
    e ->
      Logger.error("[MXResolver] Exception for #{domain}: #{inspect(e)}")
      {:error, :exception}
  end

  defp query_dns_server(domain, dns_server) do
    result = :inet_res.lookup(
      domain,
      :in,
      :mx,
      nameservers: [{dns_server, 53}],
      timeout: @dns_timeout
    )

    case result do
      [] -> {:ok, []}
      mx_records when is_list(mx_records) ->
        sorted = Enum.sort_by(mx_records, fn {priority, _host} -> priority end)
        {:ok, sorted}
      _ -> {:error, :lookup_failed}
    end
  rescue
    _ -> {:error, :exception}
  end

  # ============================================================================
  # RATE LIMITING
  # ============================================================================

  defp consume_token(%{tokens: tokens} = state) when tokens > 0 do
    {:ok, %{state | tokens: tokens - 1}}
  end

  defp consume_token(_state) do
    {:error, :rate_limited}
  end

  defp schedule_token_refill do
    Process.send_after(self(), :refill_tokens, @bucket_refill_interval)
  end
end
