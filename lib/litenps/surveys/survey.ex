defmodule Litenps.Surveys.Survey do
  @moduledoc """
  The question a site asks, and the rules for when to ask it.

  A site may have many surveys but only one `:active` at a time, since
  `/v1/config` answers with a single survey. That is enforced by a partial
  unique index, not only by this changeset.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Litenps.Accounts.Org
  alias Litenps.Sites.Site
  alias Litenps.Surveys.Targeting

  @statuses [:draft, :active, :paused]
  @max_cooldown_days 365

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "surveys" do
    field :question, :string
    field :followup_question, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :theme, :map, default: %{}
    field :cooldown_days, :integer, default: 90
    field :sample_rate, :float, default: 1.0

    embeds_one :targeting, Targeting, on_replace: :update, defaults_to_struct: true

    belongs_to :org, Org
    belongs_to :site, Site

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  The statuses a survey can have.
  """
  def statuses, do: @statuses

  @doc """
  A changeset for creating or editing a survey.

  `theme` is not settable yet: the widget defines its shape in Phase 3.
  """
  def changeset(survey, attrs) do
    survey
    |> cast(attrs, [
      :question,
      :followup_question,
      :status,
      :cooldown_days,
      :sample_rate
    ])
    |> cast_embed(:targeting, required: true)
    |> validate_required([:question, :status, :cooldown_days, :sample_rate])
    |> validate_length(:question, max: 200)
    |> validate_length(:followup_question, max: 200)
    |> validate_number(:cooldown_days,
      greater_than: 0,
      less_than_or_equal_to: @max_cooldown_days
    )
    |> validate_number(:sample_rate, greater_than: 0.0, less_than_or_equal_to: 1.0)
    |> unique_constraint(:status,
      name: :surveys_one_active_per_site,
      message: "another survey is already active on this site"
    )
  end

  @doc """
  Whether the survey is the one the widget would serve.
  """
  def active?(%__MODULE__{status: status}), do: status == :active
end
