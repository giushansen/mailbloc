defmodule MailblocWeb.API.CheckController do
  use MailblocWeb, :controller

  require Logger

  @doc """
  GET /api/check?email=test@example.com&ip=1.2.3.4

  Returns: %{risk_level: "high", reasons: ["disposable_email"]}
  """
  def check(conn, params) do
    email = params["email"]
    ip = params["ip"]

    # Strict validation
    case validate_params(email, ip) do
      :ok ->
        # Classify risk (FAST - all ETS lookups)
        result = Mailbloc.RiskClassifier.classify(%{
          email: email,
          ip: ip
        })

        Logger.info("[API] Check: email=#{inspect(email)}, ip=#{inspect(ip)}, risk=#{result.risk_level}")

        # Add cache headers for successful responses (optional)
        conn
        |> put_resp_header("cache-control", "public, max-age=300")
        |> json(result)

      {:error, :missing_params} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "missing_params",
          message: "At least one of 'email' or 'ip' must be provided"
        })

      {:error, :invalid_email} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_email",
          message: "Email must contain '@' and be properly formatted"
        })

      {:error, :invalid_ip} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_ip",
          message: "IP must be in valid IPv4 format (e.g., 192.168.1.1)"
        })
    end
  end

  # ============================================================================
  # STRICT VALIDATION
  # ============================================================================

  defp validate_params(nil, nil) do
    {:error, :missing_params}
  end

  defp validate_params(email, ip) do
    with :ok <- validate_email(email),
         :ok <- validate_ip(ip) do
      :ok
    end
  end

  defp validate_email(nil), do: :ok

  defp validate_email(email) when is_binary(email) do
    # Strict email validation
    cond do
      String.trim(email) == "" ->
        {:error, :invalid_email}

      not String.contains?(email, "@") ->
        {:error, :invalid_email}

      String.starts_with?(email, "@") or String.ends_with?(email, "@") ->
        {:error, :invalid_email}

      String.length(email) > 320 ->
        # RFC 5321 max length
        {:error, :invalid_email}

      # Basic structure check: localpart@domain
      not Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email) ->
        {:error, :invalid_email}

      true ->
        :ok
    end
  end

  defp validate_email(_), do: {:error, :invalid_email}

  defp validate_ip(nil), do: :ok

  defp validate_ip(ip) when is_binary(ip) do
    # Strict IPv4 validation
    case String.split(ip, ".") do
      [a, b, c, d] ->
        if valid_ipv4_octets?([a, b, c, d]) do
          :ok
        else
          {:error, :invalid_ip}
        end

      _ ->
        {:error, :invalid_ip}
    end
  end

  defp validate_ip(_), do: {:error, :invalid_ip}

  defp valid_ipv4_octets?(octets) do
    Enum.all?(octets, fn octet ->
      case Integer.parse(octet) do
        {num, ""} when num >= 0 and num <= 255 -> true
        _ -> false
      end
    end)
  end
end
