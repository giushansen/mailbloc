defmodule MailblocWeb.API.CheckControllerTest do
  use MailblocWeb.ConnCase, async: false

  setup do
    # Create ETS tables
    create_test_tables()
    load_test_data()

    on_exit(fn ->
      cleanup_test_tables()
    end)

    :ok
  end

  describe "GET /api/check" do
    test "returns high risk for disposable email", %{conn: conn} do
      conn = get(conn, "/api/check", %{email: "test@tempmail.com"})

      assert json_response(conn, 200) == %{
        "risk_level" => "high",
        "reasons" => ["disposable_email"]
      }
    end

    test "returns low risk for Gmail", %{conn: conn} do
      conn = get(conn, "/api/check", %{email: "john@gmail.com"})

      assert json_response(conn, 200) == %{
        "risk_level" => "low",
        "reasons" => ["free_email"]
      }
    end

    test "returns none risk for corporate email", %{conn: conn} do
      :ets.insert(:mx_cache, {"acme.com", :valid_mx})

      conn = get(conn, "/api/check", %{email: "john@acme.com"})

      assert json_response(conn, 200) == %{
        "risk_level" => "none",
        "reasons" => []
      }
    end

    test "returns high risk for TOR IP", %{conn: conn} do
      conn = get(conn, "/api/check", %{ip: "185.220.101.1"})

      assert json_response(conn, 200) == %{
        "risk_level" => "high",
        "reasons" => ["tor_network_ip"]
      }
    end

    test "returns 400 for missing parameters", %{conn: conn} do
      conn = get(conn, "/api/check")

      assert json_response(conn, 400) == %{
        "error" => "missing_params",
        "message" => "At least one of 'email' or 'ip' must be provided"
      }
    end

    test "returns 400 for invalid email", %{conn: conn} do
      conn = get(conn, "/api/check", %{email: "invalid"})

      assert json_response(conn, 400) == %{
        "error" => "invalid_email",
        "message" => "Email must contain '@' and be properly formatted"
      }
    end

    test "returns 400 for invalid IP", %{conn: conn} do
      conn = get(conn, "/api/check", %{ip: "999.999.999.999"})

      assert json_response(conn, 400) == %{
        "error" => "invalid_ip",
        "message" => "IP must be in valid IPv4 format (e.g., 192.168.1.1)"
      }
    end

    test "handles both email and IP", %{conn: conn} do
      conn = get(conn, "/api/check", %{
        email: "john@gmail.com",
        ip: "203.0.113.1"
      })

      response = json_response(conn, 200)
      assert response["risk_level"] == "medium"
      assert "vpn_ip" in response["reasons"]
    end
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp create_test_tables do
    tables = [
      :tor_network_ip,
      :vpn_ip,
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
      :tor_network_ip,
      :vpn_ip,
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
    :ets.insert(:tor_network_ip, {"185.220.101.1", true})
    :ets.insert(:vpn_ip, {"203.0.113.1", true})
    :ets.insert(:disposable_email, {"tempmail.com", true})
    :ets.insert(:privacy_email, {"simplelogin.com", true})
  end
end
