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

# Delete existing data
IO.puts("🧹 Cleaning up existing data...")
Repo.delete_all(User)
IO.puts("✅ Cleanup complete\n")

# Password for all users
password = "Password_123456"
hashed_password = Bcrypt.hash_pwd_salt(password)

# Create user using standard Phoenix changeset pattern
IO.puts("👥 Creating user")
email = "seed@example.com"

user =
  %User{}
  |> User.changeset(%{
    email: email,
    hashed_password: hashed_password,
    confirmed_at: DateTime.truncate(DateTime.utc_now(), :second)
  })
  |> Repo.insert!()

IO.puts("\n✅ User created successfully")
IO.puts("   Email: #{email}")
IO.puts("   Password: #{password}")
IO.puts("   API Token: #{user.api_token}")
IO.puts("\n=========================\n")
