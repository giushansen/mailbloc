# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Mailbloc.Repo.insert!(%Mailbloc.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.
alias Mailbloc.Repo
alias Mailbloc.Accounts.User

# Delete existing data (including alerts)
IO.puts("🧹 Cleaning up existing data...")
Repo.delete_all(User)
IO.puts("✅ Cleanup complete\n")

# Password for all users
password = "Password_123456"
hashed_password = Bcrypt.hash_pwd_salt(password)

# Create 4 users with different timezones and "castle" plan
IO.puts("👥 Creating user")
email = "seed@example.com"

Repo.insert!(%User{
  email: email,
  hashed_password: hashed_password,
  confirmed_at: DateTime.truncate(DateTime.utc_now(), :second)
})

IO.puts("\n✅ User created successfully\n")
IO.puts("=========================\n")
