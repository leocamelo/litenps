defmodule Litenps.Surveys.Targeting do
  @moduledoc """
  When a survey is allowed to show.

  Stored as JSON on the survey rather than as columns: these rules are read as
  one blob by `/v1/config` and are expected to grow, and none of them is ever
  queried on its own.

  Targeting is decided server-side — see `docs/ARCHITECTURE.md` §6 — so the
  widget never learns the rules a visitor did not match.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @max_patterns 20
  @max_delay_seconds 300

  @primary_key false
  embedded_schema do
    field :url_patterns, {:array, :string}, default: []
    field :delay_seconds, :integer, default: 0
    field :device, Ecto.Enum, values: [:all, :desktop, :mobile], default: :all
  end

  @doc """
  A changeset for the targeting rules.

  An empty `url_patterns` means every page. Patterns match the path and may use
  `*` as a wildcard, as in `/pricing*`.
  """
  def changeset(targeting, attrs) do
    targeting
    |> cast(split_pattern_text(attrs), [:url_patterns, :delay_seconds, :device])
    |> update_change(:url_patterns, &clean_patterns/1)
    |> validate_length(:url_patterns, max: @max_patterns)
    |> validate_number(:delay_seconds,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: @max_delay_seconds
    )
    |> validate_required([:delay_seconds, :device])
  end

  defp split_pattern_text(attrs) do
    Map.new(attrs, fn
      {key, value} when key in ["url_patterns", :url_patterns] and is_binary(value) ->
        {key, String.split(value, ~r/[\s,]+/, trim: true)}

      pair ->
        pair
    end)
  end

  defp clean_patterns(patterns) do
    patterns
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end
end
