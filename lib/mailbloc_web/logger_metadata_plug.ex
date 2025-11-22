defmodule MailblocWeb.LoggerMetadataPlug do
  @moduledoc """
  Adds remote IP and user email to Logger metadata for every request.
  Lightweight and efficient - just sets metadata, no heavy processing.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    # Get remote IP - already parsed by Plug
    remote_ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    # Get user email if authenticated (from current_scope)
    user_email = get_user_email(conn)

    # Set logger metadata - this is extremely cheap (just ETS updates)
    Logger.metadata(
      remote_ip: remote_ip,
      user_email: user_email
    )

    conn
  end

  # Extract email from current_scope if user is authenticated
  defp get_user_email(%{assigns: %{current_scope: %{user: %{email: email}}}}), do: email
  defp get_user_email(_), do: nil
end
