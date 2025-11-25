defmodule Mailbloc.SignupValidator do
  require Logger

  def validate(email, ip) do
    token = System.get_env("MAILBLOC_API_TOKEN")
    params = build_params(email, ip)
    url = "https://api.mailbloc.com/check?" <> URI.encode_query(params)

    case Req.get(url, headers: [{"authorization", "Bearer #{token}"}], receive_timeout: 2000) do
      {:ok, %{status: 200, body: %{"risk_level" => risk}}} when risk in ["none", "low"] ->
        true

      {:ok, %{status: 200, body: %{"risk_level" => risk}}} ->
        log_blocked(email, ip, risk)
        false

      error ->
        Logger.error("[SignupValidator] API failed: #{inspect(error)}")
        false
    end
  end

  defp build_params(email, ip) when is_binary(email) and is_binary(ip), do: [email: email, ip: ip]
  defp build_params(email, _ip) when is_binary(email), do: [email: email]
  defp build_params(_email, ip) when is_binary(ip), do: [ip: ip]
  defp build_params(_email, _ip), do: []

  defp log_blocked(email, ip, risk) do
    spawn(fn ->
      line = "#{DateTime.utc_now()},#{ip},#{email},#{risk}\n"
      File.write(System.get_env("MAILBLOC_CSV_PATH", "blocked_signups.csv"), line, [:append])
      Logger.warning("[SignupValidator] BLOCKED #{risk}: #{email} from #{ip}")
    end)
  end
end
