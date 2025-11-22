import Config

config :mailbloc, MailblocWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto]]

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Hackney

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

config :plug, :remote_ip,
  headers: ["cf-connecting-ip", "x-forwarded-for"],
  proxies: [] # Cloudflare IPs are dynamic, handled by cf-connecting-ip

config :logger,
  level: :debug,
  default_handler: [
    config: [
      file: System.get_env("LOG_PATH") |> String.to_charlist(),
      filesync_repeat_interval: 5000,
      file_check: 5000,
      max_no_bytes: 10_000_000,
      max_no_files: 20,
      compress_on_rotate: true
    ]
  ],
  default_formatter: [
    format: "$dateT$time [$level] $metadata$message\n",
    metadata: [:request_id, :remote_ip, :user_email, :method, :path, :status, :response_time, :query_string, :request_headers]
  ]

# Disable LiveDashboard and LiveReloader logging
config :phoenix_live_dashboard, :enable_logger, false
config :phoenix_live_reload, :enable_logger, false

config :phoenix, :logger, true

config :mailbloc, :base_url, "https://mailbloc.com"
