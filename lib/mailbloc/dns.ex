defmodule Mailbloc.DNS do
  @moduledoc """
  DNS utilities for email validation.
  Public interface to MXResolver GenServer.
  """

  @doc """
  Lookup MX records for a domain.
  Returns {:ok, mx_records} or {:error, reason}
  """
  def lookup_mx(domain) do
    Mailbloc.DNS.MXResolver.lookup_mx(domain)
  end

  @doc """
  Check if domain has valid MX records.
  """
  def has_valid_mx?(domain) do
    case lookup_mx(domain) do
      {:ok, []} -> false
      {:ok, _mx_records} -> true
      {:error, _} -> false
    end
  end
end
