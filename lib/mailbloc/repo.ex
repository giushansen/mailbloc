defmodule Mailbloc.Repo do
  use Ecto.Repo,
    otp_app: :mailbloc,
    adapter: Ecto.Adapters.SQLite3
end
