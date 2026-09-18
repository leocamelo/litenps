defmodule Litenps.Sites do
  @moduledoc """
  Sites and their public API keys.

  Every function takes a `Litenps.Accounts.Scope` and only ever touches rows in
  the scope's org. Functions that receive a struct match its `org_id` against the
  scope in the function head, so a struct from another org is a crash, not a
  silent cross-tenant write.

  There is no site deletion. A site will own responses, and removing responses
  is restricted to the three paths in `docs/ARCHITECTURE.md` §7.
  """

  import Ecto.Query, warn: false

  alias Litenps.Accounts.Scope
  alias Litenps.Repo
  alias Litenps.Sites.{ApiKey, Site}

  ## Sites

  @doc """
  Lists the org's sites, by name.
  """
  @spec list_sites(Scope.t()) :: [Site.t()]
  def list_sites(%Scope{org: %{id: org_id}}) do
    Repo.all(
      from s in Site, where: s.org_id == ^org_id, order_by: [asc: s.name, asc: s.inserted_at]
    )
  end

  @doc """
  Gets one of the org's sites.

  Raises `Ecto.NoResultsError` if it does not exist or belongs to another org.
  """
  @spec get_site!(Scope.t(), Ecto.UUID.t()) :: Site.t()
  def get_site!(%Scope{org: %{id: org_id}}, id) do
    Repo.get_by!(Site, id: id, org_id: org_id)
  end

  @doc """
  Creates a site together with its first API key, so a new site can be
  installed straight away.
  """
  @spec create_site(Scope.t(), map()) :: {:ok, Site.t()} | {:error, Ecto.Changeset.t()}
  def create_site(%Scope{org: %{id: org_id}}, attrs) do
    Repo.transact(fn ->
      with {:ok, site} <-
             %Site{org_id: org_id}
             |> Site.changeset(attrs)
             |> validate_timezone()
             |> Repo.insert(),
           {:ok, _api_key} <- site |> ApiKey.build() |> Repo.insert() do
        {:ok, site}
      end
    end)
  end

  @doc """
  Updates one of the org's sites.
  """
  @spec update_site(Scope.t(), Site.t(), map()) :: {:ok, Site.t()} | {:error, Ecto.Changeset.t()}
  def update_site(%Scope{org: %{id: org_id}}, %Site{org_id: org_id} = site, attrs) do
    site
    |> Site.changeset(attrs)
    |> validate_timezone()
    |> Repo.update()
  end

  @doc """
  Returns a changeset for tracking site changes in a form.

  Build new sites as `%Site{org_id: scope.org.id}`.
  """
  @spec change_site(Scope.t(), Site.t(), map()) :: Ecto.Changeset.t()
  def change_site(%Scope{org: %{id: org_id}}, %Site{org_id: org_id} = site, attrs \\ %{}) do
    Site.changeset(site, attrs)
  end

  @doc """
  Lists the IANA timezone names a site can use, as known to Postgres.

  Postgres is the source of truth because it is where day bucketing will run.
  """
  @spec list_timezones() :: [String.t()]
  def list_timezones do
    %{rows: rows} =
      Repo.query!("""
      SELECT name FROM pg_timezone_names
      WHERE name !~ '^(posix|right)/' AND name <> 'localtime'
      ORDER BY name
      """)

    List.flatten(rows)
  end

  defp validate_timezone(changeset) do
    Ecto.Changeset.validate_change(changeset, :timezone, fn :timezone, timezone ->
      %{num_rows: found} =
        Repo.query!("SELECT 1 FROM pg_timezone_names WHERE name = $1", [timezone])

      if found > 0, do: [], else: [timezone: "is not a known timezone"]
    end)
  end

  ## API keys

  @doc """
  Lists a site's API keys, newest first, including revoked ones.
  """
  @spec list_api_keys(Scope.t(), Site.t()) :: [ApiKey.t()]
  def list_api_keys(%Scope{org: %{id: org_id}}, %Site{org_id: org_id, id: site_id}) do
    Repo.all(
      from k in ApiKey,
        where: k.org_id == ^org_id and k.site_id == ^site_id,
        order_by: [desc: k.inserted_at, desc: k.id]
    )
  end

  @doc """
  Gets one of a site's API keys.

  Raises `Ecto.NoResultsError` if it does not exist or belongs to another site
  or org.
  """
  @spec get_api_key!(Scope.t(), Site.t(), Ecto.UUID.t()) :: ApiKey.t()
  def get_api_key!(%Scope{org: %{id: org_id}}, %Site{org_id: org_id, id: site_id}, id) do
    Repo.get_by!(ApiKey, id: id, site_id: site_id, org_id: org_id)
  end

  @doc """
  Issues a new key for a site, optionally labelled. Rotating a key means issuing
  a new one, switching the snippet over, then revoking the old one.
  """
  @spec create_api_key(Scope.t(), Site.t(), map()) ::
          {:ok, ApiKey.t()} | {:error, Ecto.Changeset.t()}
  def create_api_key(%Scope{org: %{id: org_id}}, %Site{org_id: org_id} = site, attrs \\ %{}) do
    site |> ApiKey.build(attrs) |> Repo.insert()
  end

  @doc """
  Revokes a key. A revoked key is rejected by the widget endpoints.

  The last active key cannot be revoked, since that would take the site's
  widget down; issue a replacement first.
  """
  @spec revoke_api_key(Scope.t(), ApiKey.t()) ::
          {:ok, ApiKey.t()} | {:error, :already_revoked | :last_active_key}
  def revoke_api_key(%Scope{org: %{id: org_id}} = scope, %ApiKey{org_id: org_id} = api_key) do
    Repo.transact(fn ->
      site = lock_site!(scope, %Site{id: api_key.site_id, org_id: org_id})

      cond do
        not ApiKey.active?(api_key) -> {:error, :already_revoked}
        count_active_keys(scope, site) <= 1 -> {:error, :last_active_key}
        true -> api_key |> ApiKey.revoke_changeset() |> Repo.update()
      end
    end)
  end

  # Revocation checks the active count and then writes, so it serializes on the
  # site row: two concurrent revocations of a site's last two keys must not both
  # pass the check.
  defp lock_site!(%Scope{org: %{id: org_id}}, %Site{id: site_id}) do
    Repo.one!(from s in Site, where: s.id == ^site_id and s.org_id == ^org_id, lock: "FOR UPDATE")
  end

  defp count_active_keys(%Scope{org: %{id: org_id}}, %Site{id: site_id}) do
    Repo.aggregate(
      from(k in ApiKey,
        where: k.org_id == ^org_id and k.site_id == ^site_id and is_nil(k.revoked_at)
      ),
      :count
    )
  end
end
