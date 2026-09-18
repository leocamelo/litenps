defmodule Litenps.Repo.Migrations.CreateOrgs do
  use Ecto.Migration

  def change do
    create table(:orgs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    alter table(:users) do
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all)
    end

    # Every existing user gets its own organization. The new organization reuses
    # the user's id, which sidesteps correlating INSERT ... RETURNING rows back
    # to the users they were created for. The two ids are unrelated afterwards.
    execute &backfill_orgs/0, fn -> :ok end

    alter table(:users) do
      modify :org_id, :binary_id, null: false, from: {:binary_id, null: true}
    end

    create index(:users, [:org_id])
  end

  defp backfill_orgs do
    repo().query!("""
    INSERT INTO orgs (id, name, inserted_at, updated_at)
    SELECT u.id, split_part(u.email::text, '@', 1), now(), now()
    FROM users u
    WHERE u.org_id IS NULL
    """)

    repo().query!("UPDATE users SET org_id = id WHERE org_id IS NULL")
  end
end
