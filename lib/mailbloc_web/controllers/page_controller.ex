defmodule MailblocWeb.PageController do
  use MailblocWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
