defmodule MailblocWeb.NotFoundController do
  use MailblocWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:not_found)
    |> render("show.html")
  end
end
