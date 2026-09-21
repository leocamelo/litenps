defmodule Litenps.SurveysFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Litenps.Surveys` context.
  """

  alias Litenps.Surveys

  def valid_survey_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      question: "How likely are you to recommend us?",
      followup_question: "What is the main reason for your score?",
      cooldown_days: 90,
      sample_rate: 1.0
    })
  end

  def survey_fixture(scope, site, attrs \\ %{}) do
    {:ok, survey} = Surveys.create_survey(scope, site, valid_survey_attributes(attrs))
    survey
  end
end
