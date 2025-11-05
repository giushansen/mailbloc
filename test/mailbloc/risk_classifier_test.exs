defmodule Mailbloc.RiskClassifierTest do
  use ExUnit.Case, async: false

  alias Mailbloc.RiskClassifier

  setup do
    # Create ETS tables
    create_test_tables()
    load_test_data()

    on_exit(fn ->
      cleanup_test_tables()
    end)

    :ok
  end

  describe "email classification" do
    test "disposable email returns high risk" do
      result = RiskClassifier.classify(%{email: "test@tempmail.com"})

      assert result.risk_level == "high"
      assert "disposable_email" in result.reasons
    end

    test "privacy email returns medium risk" do
      result = RiskClassifier.classify(%{email: "user@simplelogin.com"})

      assert result.risk_level == "medium"
      assert "privacy_email" in result.reasons
    end

    test "free email returns low risk" do
      result = RiskClassifier.classify(%{email: "john@gmail.com"})

      assert result.risk_level == "low"
      assert "free_email" in result.reasons
    end

    test "clean corporate email returns none risk with empty reasons" do
      # Mock MX cache for corporate domain
      :ets.insert(:mx_cache, {"acme.com", :valid_mx})

      result = RiskClassifier.classify(%{email: "john@acme.com"})

      assert result.risk_level == "none"
      assert result.reasons == []
    end

    test "invalid email returns high risk" do
      # Mock MX cache for invalid domain
      :ets.insert(:mx_cache, {"invalid-domain.com", :no_mx})

      result = RiskClassifier.classify(%{email: "test@invalid-domain.com"})

      assert result.risk_level == "high"
      assert "invalid_email" in result.reasons
    end
  end

  describe "IP classification" do
    test "TOR IP returns high risk" do
      result = RiskClassifier.classify(%{ip: "185.220.101.1"})

      assert result.risk_level == "high"
      assert "tor_network_ip" in result.reasons
    end

    test "criminal network IP returns high risk" do
      result = RiskClassifier.classify(%{ip: "1.2.3.1"})

      assert result.risk_level == "high"
      assert "criminal_network_ip" in result.reasons
    end

    test "VPN IP returns medium risk" do
      result = RiskClassifier.classify(%{ip: "203.0.113.1"})

      assert result.risk_level == "medium"
      assert "vpn_ip" in result.reasons
    end

    test "clean IP returns none risk" do
      result = RiskClassifier.classify(%{ip: "8.8.8.8"})

      assert result.risk_level == "none"
      assert result.reasons == []
    end
  end

  describe "combined email + IP classification" do
    test "high risk IP overrides good email" do
      :ets.insert(:mx_cache, {"acme.com", :valid_mx})

      result = RiskClassifier.classify(%{
        email: "john@acme.com",
        ip: "185.220.101.1"
      })

      assert result.risk_level == "high"
      assert "tor_network_ip" in result.reasons
    end

    test "disposable email overrides clean IP" do
      result = RiskClassifier.classify(%{
        email: "test@tempmail.com",
        ip: "8.8.8.8"
      })

      assert result.risk_level == "high"
      assert "disposable_email" in result.reasons
    end

    test "corporate email can upgrade low IP risk" do
      :ets.insert(:mx_cache, {"acme.com", :valid_mx})
      :ets.insert(:reported_ip, {"198.51.100.1", true})

      result = RiskClassifier.classify(%{
        email: "john@acme.com",
        ip: "198.51.100.1"
      })

      assert result.risk_level == "none"
      assert result.reasons == []
    end

    test "free email downgrades clean IP" do
      result = RiskClassifier.classify(%{
        email: "john@gmail.com",
        ip: "8.8.8.8"
      })

      assert result.risk_level == "low"
      assert "free_email" in result.reasons
    end
  end

  describe "edge cases" do
    test "no email or IP returns none risk" do
      result = RiskClassifier.classify(%{})

      assert result.risk_level == "none"
      assert result.reasons == []
    end

    test "only email provided works correctly" do
      result = RiskClassifier.classify(%{email: "test@tempmail.com"})

      assert result.risk_level == "high"
      assert "disposable_email" in result.reasons
    end

    test "only IP provided works correctly" do
      result = RiskClassifier.classify(%{ip: "185.220.101.1"})

      assert result.risk_level == "high"
      assert "tor_network_ip" in result.reasons
    end
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp create_test_tables do
    tables = [
      :criminal_network_ip,
      :malicious_ip,
      :tor_network_ip,
      :recent_attacker_ip,
      :week_attacker_ip,
      :suspicious_ip,
      :vpn_ip,
      :datacenter_ip,
      :reported_ip,
      :old_attacker_ip,
      :disposable_email,
      :privacy_email,
      :mx_cache
    ]

    Enum.each(tables, fn name ->
      unless :ets.whereis(name) != :undefined do
        :ets.new(name, [:set, :public, :named_table, read_concurrency: true])
      end
    end)
  end

  defp cleanup_test_tables do
    tables = [
      :criminal_network_ip,
      :malicious_ip,
      :tor_network_ip,
      :recent_attacker_ip,
      :week_attacker_ip,
      :suspicious_ip,
      :vpn_ip,
      :datacenter_ip,
      :reported_ip,
      :old_attacker_ip,
      :disposable_email,
      :privacy_email,
      :mx_cache
    ]

    Enum.each(tables, fn name ->
      # Check if table exists before trying to delete
      if :ets.whereis(name) != :undefined do
        try do
          :ets.delete(name)
        rescue
          ArgumentError -> :ok  # Table was deleted by another process, that's fine
        end
      end
    end)
  end

  defp load_test_data do
    # High risk IPs
    :ets.insert(:criminal_network_ip, {"1.2.3.1", true})
    :ets.insert(:malicious_ip, {"5.6.7.8", true})
    :ets.insert(:tor_network_ip, {"185.220.101.1", true})
    :ets.insert(:recent_attacker_ip, {"9.10.11.12", true})

    # Medium risk IPs
    :ets.insert(:vpn_ip, {"203.0.113.1", true})
    :ets.insert(:datacenter_ip, {"13.14.15.16", true})

    # Low risk IPs
    :ets.insert(:reported_ip, {"198.51.100.1", true})

    # High risk emails
    :ets.insert(:disposable_email, {"tempmail.com", true})
    :ets.insert(:disposable_email, {"guerrillamail.com", true})

    # Medium risk emails
    :ets.insert(:privacy_email, {"simplelogin.com", true})
    :ets.insert(:privacy_email, {"anonaddy.com", true})
  end
end
