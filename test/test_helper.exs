Logger.configure(level: :error)

# Ensure ETS tables exist before tests run
Process.sleep(200)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Mailbloc.Repo, :manual)
