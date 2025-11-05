defmodule Mailbloc.BlocklistFixtures do
  @moduledoc """
  Generates fake blocklist files for testing
  """

  def create_test_blocklists(dir) do
    File.mkdir_p!(dir)

    # Create fake IP blocklists
    create_file(dir, "criminal_network_ip.txt", """
    # Spamhaus DROP list
    1.2.3.0/24 ; SBL12345
    10.0.0.1
    192.168.1.100
    """)

    create_file(dir, "malicious_ip.txt", """
    # IPsum Level 8
    5.6.7.8 8
    9.10.11.12 8
    """)

    create_file(dir, "tor_network_ip.txt", """
    185.220.101.1
    185.220.101.2
    """)

    create_file(dir, "vpn_ip.txt", """
    # VPN IPs
    203.0.113.1
    203.0.113.2
    """)

    # Create fake email blocklists
    create_file(dir, "disposable_email.txt", """
    # Disposable emails
    tempmail.com
    guerrillamail.com
    10minutemail.com
    """)

    create_file(dir, "privacy_email.txt", """
    # Privacy forwards
    simplelogin.com
    anonaddy.com
    """)

    :ok
  end

  defp create_file(dir, filename, content) do
    File.write!(Path.join(dir, filename), content)
  end
end
