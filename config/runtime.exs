import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/mailbloc start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :mailbloc, MailblocWeb.Endpoint, server: true
end

if config_env() == :dev do
  config :mailbloc, :stripe_publishable_key, System.get_env("STRIPE_PUBLISHABLE_KEY")
  config :mailbloc, :stripe_secret_key, System.get_env("STRIPE_SECRET_KEY")
  config :stripity_stripe, api_key: System.get_env("STRIPE_SECRET_KEY")
  config :mailbloc, :stripe_webhook_secret, System.get_env("STRIPE_WEBHOOK_SECRET")
  config :mailbloc, :stripe_monthly_price_id, System.get_env("STRIPE_MONTHLY_PRICE_ID")
  config :mailbloc, :stripe_yearly_price_id, System.get_env("STRIPE_YEARLY_PRICE_ID")
end

if config_env() == :prod do
  # Load all environment variables from .env
  config :mailbloc, :mix_env, System.get_env("MIX_ENV")
  config :mailbloc, :host, System.get_env("HOST")
  config :mailbloc, :phx_host, System.get_env("PHX_HOST")
  config :mailbloc, :phx_server, System.get_env("PHX_SERVER")
  config :mailbloc, :port, System.get_env("PORT")

  config :mailbloc, :github_repo, System.get_env("GITHUB_REPO")
  config :mailbloc, :github_token, System.get_env("GITHUB_TOKEN")
  config :mailbloc, :github_branch, System.get_env("GITHUB_BRANCH")

  config :mailbloc, :google_client_id, System.get_env("GOOGLE_CLIENT_ID")
  config :mailbloc, :google_client_secret, System.get_env("GOOGLE_CLIENT_SECRET")

  config :mailbloc, :mailgun_api_key, System.get_env("MAILGUN_API_KEY")
  config :mailbloc, :mailgun_domain, System.get_env("MAILGUN_DOMAIN")

  config :mailbloc, :stripe_publishable_key, System.get_env("STRIPE_PUBLISHABLE_KEY")
  config :mailbloc, :stripe_secret_key, System.get_env("STRIPE_SECRET_KEY")
  config :stripity_stripe, api_key: System.get_env("STRIPE_SECRET_KEY")
  config :mailbloc, :stripe_webhook_secret, System.get_env("STRIPE_WEBHOOK_SECRET")
  config :mailbloc, :stripe_monthly_price_id, System.get_env("STRIPE_MONTHLY_PRICE_ID")
  config :mailbloc, :stripe_yearly_price_id, System.get_env("STRIPE_YEARLY_PRICE_ID")

  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/mailbloc/mailbloc.db
      """

  config :mailbloc, Mailbloc.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "mailbloc.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :mailbloc, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :mailbloc, MailblocWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0},
      port: port
    ],
    https: [
    ip: {0, 0, 0, 0},
    port: 4001,
    cipher_suite: :strong,
    certfile: System.get_env("SSL_CERT_PATH"),
    keyfile: System.get_env("SSL_KEY_PATH")
    ],
    secret_key_base: secret_key_base

  # Mailer configuration
  config :mailbloc, Mailbloc.Mailer,
    adapter: Swoosh.Adapters.Mailgun,
    api_key: System.get_env("MAILGUN_API_KEY"),
    domain: System.get_env("MAILGUN_DOMAIN")
end
