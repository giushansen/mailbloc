defmodule MailblocWeb.Router do
  use MailblocWeb, :router

  import MailblocWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MailblocWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MailblocWeb.API do
    pipe_through :api

    get "/check", CheckController, :check
  end

  scope "/", MailblocWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/pricing", PageController, :pricing
    get "/help", PageController, :help
    get "/privacy", PageController, :privacy
    get "/terms", PageController, :terms

    get "/vs", PageController, :vs
    get "/vs/ipqs", PageController, :vs_ipqs
    get "/vs/castle", PageController, :vs_castle
    get "/vs/apivoid", PageController, :vs_apivoid
    get "/vs/antideo", PageController, :vs_antideo

    get "/not-found", NotFoundController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", MailblocWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:mailbloc, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MailblocWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", MailblocWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{MailblocWeb.UserAuth, :require_authenticated}] do
      live "/welcome", UserLive.Welcome

      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", MailblocWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{MailblocWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  # Catch-all route for unmatched routes
  scope "/", MailblocWeb do
    pipe_through :browser

    match :*, "/*path", NotFoundController, :show
  end
end
