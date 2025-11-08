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

  def vs(conn, _params) do
    conn
    |> assign(:page_title, "Mailbloc vs Competitors: Email & IP Validation Comparison")
    |> assign(:meta_description, "Compare Mailbloc with IPQS, Castle.io, APIVoid, and Antideo for email and IP validation. See features, pricing, and which fraud prevention tool is best for stopping fake sign-ups.")
    |> render(:vs)
  end

  def vs_ipqs(conn, _params) do
    conn
    |> assign(:page_title, "Mailbloc vs IPQS: Forever Free Alternative for Email & IP Validation")
    |> assign(:meta_description, "Compare Mailbloc and IPQS for fraud prevention. Get unlimited free API calls vs 5K/month limit. Save $1,932+ annually with simple, developer-friendly signup validation at $39/mo vs $100s-$1,000s.")
    |> render(:vs_ipqs)
  end

  def vs_castle(conn, _params) do
    conn
    |> assign(:page_title, "Mailbloc vs Castle.io: Simple Signup Validation vs Account Security")
    |> assign(:meta_description, "Compare Mailbloc and Castle.io for preventing fake signups. Forever free unlimited API calls vs 1K/month. Save $51,532 annually with focused email/IP validation at $39/mo vs enterprise pricing.")
    |> render(:vs_castle)
  end

  def vs_apivoid(conn, _params) do
    conn
    |> assign(:page_title, "Mailbloc vs APIVoid: Application Signup Validation vs Threat Intelligence")
    |> assign(:meta_description, "Compare Mailbloc and APIVoid for email and IP validation. Developer-friendly signup blocking vs security analyst toolkit. One simple endpoint vs 20+ APIs for different use cases.")
    |> render(:vs_apivoid)
  end

  def vs_antideo(conn, _params) do
    conn
    |> assign(:page_title, "Mailbloc vs Antideo: Unlimited Free vs 10 Requests Per Hour")
    |> assign(:meta_description, "Compare Mailbloc and Antideo for email and IP validation. Production-ready unlimited free plan vs restrictive 10 req/hour limit. ML-powered detection at $39/mo vs basic validation at $5-50/mo.")
    |> render(:vs_antideo)
  end
end
