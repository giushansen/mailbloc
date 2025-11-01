defmodule MailblocWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MailblocWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the site layout for marketing pages

  ## Examples

      <Layouts.site flash={@flash}>
        <h1>Marketing Content</h1>
      </Layouts.site>
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def site(assigns) do
    ~H"""
    <.navbar current_scope={@current_scope} />

    <main class="pt-16">
      <%= render_slot(@inner_block) %>
    </main>

    <.footer />
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :live_action, :atom, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <.navbar current_scope={@current_scope} live_action={@live_action} />

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto w-full max-w-7xl space-y-4 px-4 sm:px-0">
        <%= render_slot(@inner_block) %>
      </div>
    </main>

    <.footer :if={show_footer?(assigns)} />
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  attr :current_scope, :map, default: nil
  attr :app, :map, default: nil
  attr :live_action, :atom, default: nil

  defp navbar(assigns) do
    ~H"""
    <nav class="navbar w-full fixed top-0 z-10 bg-base-100 shadow-md">
      <div class="flex-1">
        <.logo_link logged_in={logged_in?(assigns)} />
      </div>
      <.user_menu current_scope={@current_scope} />
    </nav>
    """
  end

  attr :current_scope, :map, default: nil

  defp user_menu(assigns) do
    ~H"""
    <div class="flex-none">
      <ul class="menu menu-horizontal px-0.5 sm:px-1 lg:px-2 gap-1 sm:gap-2">
        <%= if logged_in?(assigns) do %>
          <.link href={~p"/help"} class="btn btn-ghost text-xs sm:text-sm px-1 sm:px-2 hidden sm:flex">
            <.icon name="hero-book-open" class="size-6" />
          </.link>
          <.link href={~p"/users/settings"} class="btn btn-ghost text-xs sm:text-sm px-1 sm:px-2 hidden sm:flex">
            <.icon name="hero-cog-6-tooth" class="size-6" />
          </.link>
          <.link href={~p"/users/log-out"} method="delete" class="btn btn-ghost text-xs sm:text-sm px-1 sm:px-2">
            <.icon name="hero-arrow-right-start-on-rectangle" class="size-6" />
          </.link>
        <% else %>
          <li><a href={~p"/pricing"} class="btn btn-ghost text-xs sm:text-sm px-1 sm:px-2">Pricing</a></li>
          <li><a href={~p"/help"} class="btn btn-ghost text-xs sm:text-sm px-1 sm:px-2">Docs</a></li>
          <li><a href={~p"/users/register"} class="btn btn-ghost text-xs sm:text-sm px-1 sm:px-2">Register</a></li>
          <li><a href={~p"/users/log-in"} class="btn btn-ghost text-xs sm:text-sm px-1 sm:px-2">Log in</a></li>
        <% end %>
      </ul>
    </div>
    """
  end

  attr :logged_in, :boolean, required: true

  defp logo_link(assigns) do
    ~H"""
    <a href={if @logged_in, do: ~p"/welcome", else: ~p"/"} class="flex items-center gap-2 px-2 sm:px-4">
      <img src="/images/mailbloc_logo.svg" alt="Mailbloc Logo" class="h-8 w-8" />
      <span class="text-xl font-bold text-base-content">Mailbloc</span>
    </a>
    """
  end

  defp footer(assigns) do
    ~H"""
    <footer class="footer footer-center bg-base-300 text-base-content/70 p-10">
      <div class="flex flex-col items-center gap-6 w-full max-w-6xl">
        <div class="flex items-center gap-2">
          <img src="/images/mailbloc_logo.svg" alt="Mailbloc Logo" class="h-8 w-8" />
          <span class="text-lg font-semibold text-base-content">Mailbloc</span>
        </div>

        <!-- Comparisons Section -->
        <%!-- <div class="w-full">
          <h3 class="text-sm font-semibold text-base-content mb-3"><a href="/vs" class="link link-hover">Compare Mailbloc</a></h3>
          <div class="flex flex-wrap justify-center gap-x-6 gap-y-2 text-sm">
            <a href="/vs/datadog" class="link link-hover">vs Datadog</a>
            <a href="/vs/newrelic" class="link link-hover">vs New Relic</a>
          </div>
        </div> --%>

        <!-- Resources Section -->
        <div class="w-full border-t border-base-content/10 pt-4">
          <div class="flex flex-wrap justify-center gap-x-6 gap-y-2 text-sm">
            <a href="/pricing" class="link link-hover">Pricing</a>
            <a href="/help" class="link link-hover">Documentation</a>
          </div>
        </div>

        <!-- Legal & Social -->
        <div class="w-full border-t border-base-content/10 pt-4">
          <p class="mb-2">© 2025 Mailbloc. All rights reserved.</p>
          <p class="mb-3">
            A <a href="https://keybloc.io" class="link link-primary" target="_blank" rel="noopener">Keybloc Pte Ltd</a> company.
          </p>
          <div class="flex flex-wrap justify-center gap-4">
            <a href="https://x.com/keybloc_io" class="link flex items-center gap-1" target="_blank" rel="noopener" aria-label="Follow us on X">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" class="w-5 h-5 fill-current">
                <path d="M18.901 1.153h3.68l-8.04 9.19L24 22.846h-7.406l-5.8-7.584-6.638 7.584H.474l8.6-9.83L0 1.154h7.594l5.243 6.932ZM17.61 20.644h2.039L6.486 3.24H4.298Z"/>
              </svg>
            </a>
            <a href="/privacy" class="link link-primary">Privacy Policy</a>
            <a href="/terms" class="link link-primary">Terms of Service</a>
          </div>
        </div>
      </div>
    </footer>
    """
  end

  defp logged_in?(assigns), do: assigns[:current_scope] != nil

  defp show_footer?(assigns) do
    path = assigns[:request_path] || (if assigns[:conn], do: assigns[:conn].request_path, else: "")
    !logged_in?(assigns) && path in ["/", "/pricing", "/help", "/users/log-in", "/users/register"]
  end
end
