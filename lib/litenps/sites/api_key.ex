defmodule Litenps.Sites.ApiKey do
  @moduledoc """
  The public key a site's embed identifies itself with.

  Keys are rows rather than a column on the site so that a leaked key can be
  rotated: a new key is issued, the snippet is updated, and the old key is
  revoked. Any number of keys may be active; the last active one cannot be
  revoked, so a rotation never takes the widget down.

  The key is public by design — it ships in the customer's HTML — so it is
  stored in plain text and looked up directly.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Litenps.Accounts.Org
  alias Litenps.Sites.Site

  @prefix "pk_live_"

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_keys" do
    field :key, :string
    field :label, :string
    field :revoked_at, :utc_datetime

    belongs_to :org, Org
    belongs_to :site, Site

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a new, active key for the given site. `label` is an optional name to
  tell keys apart, such as where the snippet using it is installed.
  """
  def build(%Site{id: site_id, org_id: org_id}, attrs \\ %{}) do
    %__MODULE__{site_id: site_id, org_id: org_id}
    |> cast(attrs, [:label])
    |> update_change(:label, &String.trim/1)
    |> validate_length(:label, max: 60)
    |> put_change(:key, generate())
    |> unique_constraint(:key)
  end

  @doc """
  A changeset revoking the key now.
  """
  def revoke_changeset(%__MODULE__{} = api_key) do
    change(api_key, revoked_at: DateTime.utc_now(:second))
  end

  @doc """
  Whether the key is still accepted.
  """
  def active?(%__MODULE__{revoked_at: revoked_at}), do: is_nil(revoked_at)

  defp generate do
    @prefix <> Base.encode32(:crypto.strong_rand_bytes(16), case: :lower, padding: false)
  end
end
