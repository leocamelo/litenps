defmodule Litenps.Repo.Migrations.CreateSurveys do
  use Ecto.Migration

  def change do
    create table(:surveys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false

      add :site_id,
          references(:sites, type: :binary_id, with: [org_id: :org_id], on_delete: :delete_all),
          null: false

      add :question, :string, null: false
      add :followup_question, :string
      add :status, :string, null: false
      add :theme, :map, null: false, default: %{}
      add :targeting, :map, null: false, default: %{}
      add :cooldown_days, :integer, null: false
      add :sample_rate, :float, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:surveys, [:site_id])
    create index(:surveys, [:org_id])

    # /v1/config answers with *the* active survey, so a site has at most one.
    create unique_index(:surveys, [:site_id],
             where: "status = 'active'",
             name: :surveys_one_active_per_site
           )

    # Target for the composite foreign key from responses in Phase 2.
    create unique_index(:surveys, [:id, :org_id])
  end
end
