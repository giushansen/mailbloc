defmodule Mailbloc.RateLimitLoader do
  @moduledoc """
  Loads all API tokens from the database into the ETS :api_rate_limit table
  once the Repo is ready.
  """

  use GenServer
  require Logger
  import Ecto.Query, only: [from: 2]
  alias Mailbloc.{Repo, Accounts.User}

  # Public API
  def start_link(_args) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    # Create ETS table immediately
    :ets.new(:api_rate_limit, [:set, :public, :named_table, read_concurrency: true])

    # In test mode, don't query database - just use empty table
    if Application.get_env(:mailbloc, :env) == :test do
      Logger.info("[RateLimitLoader] Test mode - empty table")
      {:ok, %{}}
    else
      # In dev/prod, load from database after delay
      Process.send_after(self(), :load_tokens, 1000)
      {:ok, %{}}
    end
  end

  @impl true
  def handle_info(:load_tokens, state) do
    tokens = Repo.all(from u in User, select: u.api_token)
    current_minute = div(System.system_time(:second), 60)

    Enum.each(tokens, fn token ->
      :ets.insert(:api_rate_limit, {token, current_minute, 30})
    end)

    Logger.info("[RateLimitLoader] Loaded #{length(tokens)} API tokens into :api_rate_limit ETS table")

    {:noreply, state}
  end
end
