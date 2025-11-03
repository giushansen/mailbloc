defmodule MailblocWeb.UserLive.Welcome do
  use MailblocWeb, :live_view

  on_mount {MailblocWeb.UserAuth, :require_authenticated}

  alias Mailbloc.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, show_token: false, show_modal: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 py-8">
        <!-- Welcome Header -->
        <div class="text-center mb-12">
          <h1 class="text-4xl font-bold text-base-content mb-2">
            Welcome!
          </h1>
          <p class="text-lg text-base-content/70">
            <%= @current_scope.user.email %>
          </p>
        </div>

        <!-- API Token Card -->
        <div class="card bg-base-200 shadow-xl mb-8">
          <div class="card-body">
            <h2 class="card-title text-2xl mb-4">Your API Token</h2>

            <p class="text-base-content/70 mb-6">
              Use this token to authenticate your API requests to Mailbloc's fraud detection service.
            </p>

            <!-- Token Display with Actions -->
            <div class="flex items-center gap-2 p-4 bg-base-100 rounded-lg border border-base-300">
              <div class="flex-1 font-mono text-sm break-all">
                <%= if @show_token do %>
                  <span id="api-token"><%= @current_scope.user.api_token %></span>
                <% else %>
                  <span class="text-base-content/40">••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••</span>
                <% end %>
              </div>

              <div class="flex gap-2">
                <!-- Toggle visibility button -->
                <button
                  phx-click="toggle_token"
                  class="btn btn-ghost btn-sm"
                  title={if @show_token, do: "Hide token", else: "Show token"}
                >
                  <%= if @show_token do %>
                    <.icon name="hero-eye" class="size-5" />
                  <% else %>
                    <.icon name="hero-eye-slash" class="size-5" />
                  <% end %>
                </button>

                <!-- Copy button -->
                <button
                  :if={@show_token}
                  phx-hook="CopyToClipboard"
                  id="copyTokenBtn"
                  phx-click={Phoenix.LiveView.JS.dispatch("clipcopy", to: "#api-token")}
                  class="btn btn-ghost btn-sm"
                  title="Copy token to clipboard"
                >
                  <.icon name="hero-clipboard-document" class="size-5" />
                </button>

                <!-- Regenerate button -->
                <button
                  phx-click="confirm_regenerate"
                  class="btn btn-ghost btn-sm"
                  title="Regenerate token"
                >
                  <.icon name="hero-arrow-path" class="size-5" />
                </button>
              </div>
            </div>

            <div class="alert alert-warning mt-4">
              <.icon name="hero-exclamation-triangle" class="size-6" />
              <span>Keep your API token secure and never share it publicly. Regenerating will invalidate the old token.</span>
            </div>
          </div>
        </div>

        <!-- Quick Links -->
        <div class="card bg-base-200 shadow-xl">
          <div class="card-body">
            <h2 class="card-title text-2xl mb-4">Quick Links</h2>

            <div class="flex gap-4">
              <.link href={~p"/help"} class="btn btn-primary">
                <.icon name="hero-book-open" class="size-5" />
                View Full Documentation
              </.link>
              <.link href={~p"/users/settings"} class="btn btn-outline">
                <.icon name="hero-cog-6-tooth" class="size-5" />
                Account Settings
              </.link>
            </div>
          </div>
        </div>
      </div>

      <!-- Confirmation Modal -->
      <%= if @show_modal do %>
        <div class="modal modal-open">
          <div class="modal-box">
            <div class="text-center">
              <.icon name="hero-exclamation-triangle" class="size-16 mx-auto text-warning mb-4" />
              <h3 class="text-lg font-bold mb-2">Regenerate API Token</h3>
              <p class="text-base-content/70 mb-6">
                This will invalidate your current token. Any applications using the old token will stop working. Are you sure you want to continue?
              </p>
              <div class="modal-action justify-center">
                <button phx-click="regenerate_token" class="btn btn-warning">
                  Yes, Regenerate Token
                </button>
                <button phx-click="cancel_regenerate" class="btn btn-ghost">
                  Cancel
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("toggle_token", _params, socket) do
    {:noreply, assign(socket, show_token: !socket.assigns.show_token)}
  end

  @impl true
  def handle_event("confirm_regenerate", _params, socket) do
    {:noreply, assign(socket, show_modal: true)}
  end

  @impl true
  def handle_event("cancel_regenerate", _params, socket) do
    {:noreply, assign(socket, show_modal: false)}
  end

  @impl true
  def handle_event("regenerate_token", _params, socket) do
    case Accounts.regenerate_api_token(socket.assigns.current_scope.user) do
      {:ok, updated_user} ->
        updated_scope = %{socket.assigns.current_scope | user: updated_user}

        {:noreply,
         socket
         |> assign(current_scope: updated_scope, show_token: true, show_modal: false)
         |> put_flash(:info, "API token regenerated successfully")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(show_modal: false)
         |> put_flash(:error, "Failed to regenerate token. Please try again.")}
    end
  end
end
