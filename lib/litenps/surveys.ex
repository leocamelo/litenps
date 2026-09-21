defmodule Litenps.Surveys do
  @moduledoc """
  Surveys: the question a site asks and when it asks it.

  Like `Litenps.Sites`, every function takes a `Litenps.Accounts.Scope` and
  matches the org in the function head, so a struct from another org is a crash
  rather than a cross-tenant write.

  There is no survey deletion. A survey will own responses, and removing
  responses is restricted to the three paths in `docs/ARCHITECTURE.md` §7.
  """

  import Ecto.Query, warn: false

  alias Litenps.Accounts.Scope
  alias Litenps.Repo
  alias Litenps.Sites.Site
  alias Litenps.Surveys.Survey

  @doc """
  Lists a site's surveys, active first, then newest.
  """
  @spec list_surveys(Scope.t(), Site.t()) :: [Survey.t()]
  def list_surveys(%Scope{org: %{id: org_id}}, %Site{org_id: org_id, id: site_id}) do
    Repo.all(
      from s in Survey,
        where: s.org_id == ^org_id and s.site_id == ^site_id,
        order_by: [
          asc: fragment("case when ? = 'active' then 0 else 1 end", s.status),
          desc: s.inserted_at
        ]
    )
  end

  @doc """
  Gets one of a site's surveys.

  Raises `Ecto.NoResultsError` if it does not exist or belongs to another site
  or org.
  """
  @spec get_survey!(Scope.t(), Site.t(), Ecto.UUID.t()) :: Survey.t()
  def get_survey!(%Scope{org: %{id: org_id}}, %Site{org_id: org_id, id: site_id}, id) do
    Repo.get_by!(Survey, id: id, site_id: site_id, org_id: org_id)
  end

  @doc """
  Returns the survey the widget would serve for a site, or `nil`.
  """
  @spec get_active_survey(Scope.t(), Site.t()) :: Survey.t() | nil
  def get_active_survey(%Scope{org: %{id: org_id}}, %Site{org_id: org_id, id: site_id}) do
    Repo.get_by(Survey, site_id: site_id, org_id: org_id, status: :active)
  end

  @doc """
  Creates a survey for a site.
  """
  @spec create_survey(Scope.t(), Site.t(), map()) ::
          {:ok, Survey.t()} | {:error, Ecto.Changeset.t()}
  def create_survey(%Scope{org: %{id: org_id}}, %Site{org_id: org_id, id: site_id}, attrs) do
    %Survey{org_id: org_id, site_id: site_id}
    |> Survey.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a survey. Status changes go through here too.
  """
  @spec update_survey(Scope.t(), Survey.t(), map()) ::
          {:ok, Survey.t()} | {:error, Ecto.Changeset.t()}
  def update_survey(%Scope{org: %{id: org_id}}, %Survey{org_id: org_id} = survey, attrs) do
    survey
    |> Survey.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a changeset for tracking survey changes in a form.

  Build new surveys as `%Survey{org_id: scope.org.id, site_id: site.id}`.
  """
  @spec change_survey(Scope.t(), Survey.t(), map()) :: Ecto.Changeset.t()
  def change_survey(%Scope{org: %{id: org_id}}, %Survey{org_id: org_id} = survey, attrs \\ %{}) do
    Survey.changeset(survey, attrs)
  end
end
