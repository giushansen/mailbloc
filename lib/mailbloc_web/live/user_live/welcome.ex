defmodule MailblocWeb.UserLive.Welcome do
  use MailblocWeb, :live_view

  on_mount {MailblocWeb.UserAuth, :require_sudo_mode}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Welcome
          <:subtitle>Manage your token for your Fraud API</:subtitle>
        </.header>
      </div>
      <h1>Hello here is your token</h1>
    </Layouts.app>
    """
  end
end
