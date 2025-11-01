defmodule MailblocWeb.PageController do
  use MailblocWeb, :controller

  def home(conn, _params) do
    conn
    |> assign(:page_title, "Mailbloc · One Instant API. Transparent Protection from Fake Sign-ups.")
    |> render(:home)
  end

  def pricing(conn, _params) do
    conn
    |> assign(:page_title, "Pricing · Mailbloc")
    |> render(:pricing)
  end

  def help(conn, _params) do
    conn
    |> assign(:page_title, "Documentation · Mailbloc")
    |> render(:help)
  end

  def privacy(conn, _params) do
    conn
    |> assign(:page_title, "Privacy · Mailbloc")
    |> render(:privacy)
  end

  def terms(conn, _params) do
    conn
    |> assign(:page_title, "Terms & Conditions · Mailbloc")
    |> render(:terms)
  end

  def vs_datadog(conn, _params) do
    conn
    |> assign(:page_title, "Opsbloc vs Datadog: Affordable Web App Monitoring Alternative")
    |> assign(:meta_description, "Compare Opsbloc and Datadog for web application monitoring. See pricing, features, and why SMBs choose Opsbloc for integrated performance and security monitoring.")
    |> render(:vs_datadog)
  end

  def vs(conn, _params) do
    conn
    |> assign(:page_title, "Opsbloc: Affordable Web App Monitoring Alternative")
    |> assign(:meta_description, "Compare Opsbloc and others for web application monitoring. See pricing, features, and why SMBs choose Opsbloc for integrated performance and security monitoring.")
    |> render(:vs)
  end
end
