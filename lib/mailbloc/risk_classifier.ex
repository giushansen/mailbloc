defmodule Mailbloc.RiskClassifier do
  @moduledoc """
  Risk classification engine for signup validation.

  Returns: %{risk_level: risk_level(), reasons: [String.t()]}
  where risk_level: "high" | "medium" | "low" | "none"

  Quality hierarchy:
  - NONE: Corporate email with valid MX (clean, no reasons)
  - LOW: Free providers (Gmail, Yahoo)
  - MEDIUM: Privacy forwards, suspicious IPs
  - HIGH: Disposable emails, malicious IPs
  """

  require Logger

  @type risk_level :: :none | :low | :medium | :high
  @type classification :: %{risk_level: String.t(), reasons: [String.t()]}

  # Trusted free email providers
  @trusted_providers ~w(
    gmail.com googlemail.com
    outlook.com hotmail.com live.com msn.com
    yahoo.com ymail.com
    icloud.com me.com mac.com
    aol.com protonmail.com proton.me zoho.com
  )

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  @doc """
  Classify risk for email and/or IP address.

  ## Examples
      iex> classify(%{email: "john@acme.com"})
      %{risk_level: "none", reasons: []}

      iex> classify(%{ip: "1.2.3.4"})
      %{risk_level: "high", reasons: ["tor_network_ip"]}

      iex> classify(%{email: "test@tempmail.com", ip: "1.2.3.4"})
      %{risk_level: "high", reasons: ["tor_network_ip", "disposable_email"]}
  """
  @spec classify(map()) :: classification()
  def classify(params) do
    %{risk_level: :none, reasons: []}
    |> maybe_classify_ip(params[:ip])
    |> maybe_classify_email(params[:email])
    |> finalize_classification()
  end

  # ============================================================================
  # IP CLASSIFICATION PIPELINE
  # ============================================================================

  defp maybe_classify_ip(state, nil), do: state

  defp maybe_classify_ip(state, ip) do
    ip
    |> check_ip_risk()
    |> merge_classification(state)
  end

  defp check_ip_risk(ip) do
    cond do
      reason = check_high_risk_ip(ip) ->
        {:high, [reason]}

      reason = check_medium_risk_ip(ip) ->
        {:medium, [reason]}

      reason = check_low_risk_ip(ip) ->
        {:low, [reason]}

      true ->
        {:none, []}
    end
  end

  defp check_high_risk_ip(ip) do
    [
      {:criminal_network_ip, "criminal_network_ip"},
      {:malicious_ip, "malicious_ip"},
      {:tor_network_ip, "tor_network_ip"},
      {:recent_attacker_ip, "recent_attacker_ip"}
    ]
    |> find_match(ip)
  end

  defp check_medium_risk_ip(ip) do
    [
      {:week_attacker_ip, "week_attacker_ip"},
      {:suspicious_ip, "suspicious_ip"},
      {:vpn_ip, "vpn_ip"},
      {:datacenter_ip, "datacenter_ip"},
      {:old_attacker_ip, "old_attacker_ip"}
    ]
    |> find_match(ip)
  end

  defp check_low_risk_ip(ip) do
    [
      {:reported_ip, "reported_ip"},
    ]
    |> find_match(ip)
  end

  # ============================================================================
  # EMAIL CLASSIFICATION PIPELINE
  # ============================================================================

  defp maybe_classify_email(state, nil), do: state

  defp maybe_classify_email(state, email) do
    email
    |> extract_domain()
    |> check_email_risk()
    |> merge_classification(state)
  end

  defp check_email_risk(domain) do
    cond do
      disposable_email?(domain) ->
        {:high, ["disposable_email"]}

      privacy_email?(domain) ->
        {:medium, ["privacy_email"]}

      trusted_provider?(domain) ->
        {:low, ["free_email"]}

      true ->
        check_corporate_email(domain)
    end
  end

  defp check_corporate_email(domain) do
    case lookup_mx_cached(domain) do
      :valid_mx -> {:none, []} # CLEAN - no reasons!
      :no_mx -> {:high, ["invalid_email"]}
    end
  end

  # ============================================================================
  # EMAIL TYPE CHECKS
  # ============================================================================

  defp disposable_email?(domain), do: in_ets?(:disposable_email, domain)

  defp privacy_email?(domain), do: in_ets?(:privacy_email, domain)

  defp trusted_provider?(domain), do: domain in @trusted_providers

  # ============================================================================
  # MX VALIDATION WITH CACHE
  # ============================================================================

  defp lookup_mx_cached(domain) do
    case :ets.lookup(:mx_cache, domain) do
      [{^domain, result}] ->
        result

      [] ->
        perform_mx_lookup(domain)
    end
  end

  defp perform_mx_lookup(domain) do
    result =
      case Mailbloc.DNS.lookup_mx(domain) do
        {:ok, []} -> :no_mx
        {:ok, _mx_records} -> :valid_mx
        {:error, _reason} -> :no_mx
      end

    :ets.insert(:mx_cache, {domain, result})
    Logger.debug("[RiskClassifier] MX lookup: #{domain} -> #{result}")
    result
  end

  # ============================================================================
  # CLASSIFICATION MERGING LOGIC
  # ============================================================================

  defp merge_classification({new_risk, new_reasons}, %{risk_level: current_risk, reasons: current_reasons}) do
    final_risk = resolve_risk_priority(current_risk, new_risk)

    final_reasons =
      cond do
        # Corporate email upgraded LOW IP to NONE - clear all reasons (clean!)
        current_risk == :low and new_risk == :none and final_risk == :none ->
          []

        # Free email downgraded NONE to LOW - use only email reason
        current_risk == :none and new_risk == :low and final_risk == :low ->
          new_reasons

        # New risk won and it's not NONE - combine reasons
        final_risk == new_risk and new_risk != :none ->
          (new_reasons ++ current_reasons) |> Enum.uniq()

        # Current risk won - keep only current reasons
        final_risk == current_risk ->
          current_reasons

        # Fallback: combine if neither matched
        true ->
          (new_reasons ++ current_reasons) |> Enum.uniq()
      end

    %{risk_level: final_risk, reasons: final_reasons}
  end

  # Risk priority resolution (RESTORED ORIGINAL VERSION)
  defp resolve_risk_priority(current, new) do
    risk_order = %{high: 4, medium: 3, low: 2, none: 1}

    cond do
      # HIGH risk always wins
      current == :high or new == :high ->
        :high

      # MEDIUM risk wins unless current is HIGH
      current == :medium or new == :medium ->
        :medium

      # Email can upgrade LOW IP to NONE (corporate email)
      current == :low and new == :none ->
        :none

      # Email can downgrade NONE IP to LOW (free email)
      current == :none and new == :low ->
        :low

      # Otherwise take the higher risk
      risk_order[current] >= risk_order[new] ->
        current

      true ->
        new
    end
  end

  # ============================================================================
  # UTILITIES
  # ============================================================================

  defp find_match(checklist, key) do
    checklist
    |> Enum.find_value(fn {table, reason} ->
      if in_ets?(table, key), do: reason
    end)
  end

  defp in_ets?(table, key) do
    table_str = Atom.to_string(table)

    cond do
      # IP tables - use IPMatcher (handles CIDR)
      String.ends_with?(table_str, "_ip") ->
        Mailbloc.IPMatcher.matches?(table, key)

      # Email tables - exact match only
      true ->
        case :ets.lookup(table, key) do
          [] -> false
          _ -> true
        end
    end
  end

  defp extract_domain(email) do
    email
    |> String.split("@")
    |> List.last()
    |> String.downcase()
    |> String.trim()
  end

  defp finalize_classification(%{risk_level: level, reasons: reasons}) do
    %{
      risk_level: Atom.to_string(level),
      reasons: reasons
    }
  end
end
