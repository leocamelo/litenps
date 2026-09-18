defmodule Litenps.Repo.Migrations.CreateSites do
  use Ecto.Migration

  def change do
    create table(:sites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :allowed_origins, {:array, :string}, null: false, default: []
      add :timezone, :string, null: false
      add :data_retention_days, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sites, [:org_id])

    # Target for composite foreign keys from tenant-owned children, so Postgres
    # rejects a child row whose org_id disagrees with its site's.
    create unique_index(:sites, [:id, :org_id])

    create table(:api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false

      add :site_id,
          references(:sites, type: :binary_id, with: [org_id: :org_id], on_delete: :delete_all),
          null: false

      add :key, :string, null: false
      add :label, :string
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:api_keys, [:key])
    create index(:api_keys, [:site_id])
    create index(:api_keys, [:org_id])
  end
end
