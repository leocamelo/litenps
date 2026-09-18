defmodule Litenps.Accounts.Org do
  @moduledoc """
  An organization is the tenant.

  Every tenant-owned row in the system carries an `org_id`, and every context
  function is scoped to one organization through `Litenps.Accounts.Scope`.

  A user belongs to exactly one organization, which is created for them at
  registration. That is what lets the scope resolve an organization from the
  session alone, with no organization picker anywhere in the interface.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Litenps.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "orgs" do
    field :name, :string

    has_many :users, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for creating or renaming an organization.
  """
  def changeset(org, attrs) do
    org
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 160)
  end
end
