# Mailbloc

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

# Check status
```
Mailbloc.BlocklistLoader.status()
# => %{
#   last_update: ~U[2025-01-15 10:30:00Z],
#   last_status: :ok,
#   update_count: 5,
#   next_update: "In 24.0 hours",
#   blocklist_count: 12,
#   table_stats: %{
#     criminal_network_ip: 1523,
#     disposable_email: 45234,
#     tor_network_ip: 1891,
#     ...
#   }
# }

# Force update now
Mailbloc.BlocklistLoader.update_now()
# => :ok
```
