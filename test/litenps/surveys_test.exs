defmodule Litenps.SurveysTest do
  use Litenps.DataCase, async: true

  import Litenps.AccountsFixtures
  import Litenps.SitesFixtures
  import Litenps.SurveysFixtures

  alias Litenps.Surveys
  alias Litenps.Surveys.{Survey, Targeting}

  setup do
    scope = org_scope_fixture()
    %{scope: scope, site: site_fixture(scope), other_scope: org_scope_fixture()}
  end

  describe "create_survey/3" do
    test "creates a draft with default targeting", %{scope: scope, site: site} do
      assert {:ok, survey} = Surveys.create_survey(scope, site, valid_survey_attributes())

      assert survey.status == :draft
      assert survey.org_id == scope.org.id
      assert survey.site_id == site.id
      assert survey.cooldown_days == 90
      assert survey.sample_rate == 1.0
      assert %Targeting{url_patterns: [], delay_seconds: 0, device: :all} = survey.targeting
    end

    test "requires a question", %{scope: scope, site: site} do
      {:error, changeset} = Surveys.create_survey(scope, site, %{question: ""})

      assert %{question: ["can't be blank"]} = errors_on(changeset)
    end

    test "bounds cooldown and sample rate", %{scope: scope, site: site} do
      {:error, changeset} =
        Surveys.create_survey(
          scope,
          site,
          valid_survey_attributes(%{cooldown_days: 0, sample_rate: 1.5})
        )

      assert %{cooldown_days: [_], sample_rate: [_]} = errors_on(changeset)
    end

    test "accepts targeting rules", %{scope: scope, site: site} do
      {:ok, survey} =
        Surveys.create_survey(
          scope,
          site,
          valid_survey_attributes(%{
            targeting: %{
              "url_patterns" => "/pricing*\n /checkout* ,/pricing*",
              "delay_seconds" => 15,
              "device" => "mobile"
            }
          })
        )

      assert survey.targeting.url_patterns == ["/pricing*", "/checkout*"]
      assert survey.targeting.delay_seconds == 15
      assert survey.targeting.device == :mobile
    end

    test "bounds the targeting delay", %{scope: scope, site: site} do
      {:error, changeset} =
        Surveys.create_survey(
          scope,
          site,
          valid_survey_attributes(%{targeting: %{"delay_seconds" => 301}})
        )

      assert %{targeting: %{delay_seconds: [_]}} = errors_on(changeset)
    end

    test "refuses another org's site", %{scope: scope, other_scope: other_scope} do
      other_site = site_fixture(other_scope)

      assert_raise FunctionClauseError, fn ->
        Surveys.create_survey(scope, other_site, valid_survey_attributes())
      end
    end
  end

  describe "one active survey per site" do
    test "a second active survey is refused", %{scope: scope, site: site} do
      survey_fixture(scope, site, %{status: :active})

      {:error, changeset} =
        Surveys.create_survey(scope, site, valid_survey_attributes(%{status: :active}))

      assert %{status: ["another survey is already active on this site"]} = errors_on(changeset)
    end

    test "activating a second survey is refused", %{scope: scope, site: site} do
      survey_fixture(scope, site, %{status: :active})
      draft = survey_fixture(scope, site)

      assert {:error, changeset} = Surveys.update_survey(scope, draft, %{status: :active})
      assert %{status: [_]} = errors_on(changeset)
    end

    test "another site in the same org may have its own active survey", %{
      scope: scope,
      site: site
    } do
      survey_fixture(scope, site, %{status: :active})
      other_site = site_fixture(scope)

      assert {:ok, %Survey{status: :active}} =
               Surveys.create_survey(
                 scope,
                 other_site,
                 valid_survey_attributes(%{status: :active})
               )
    end

    test "pausing frees the slot", %{scope: scope, site: site} do
      active = survey_fixture(scope, site, %{status: :active})
      draft = survey_fixture(scope, site)

      {:ok, _paused} = Surveys.update_survey(scope, active, %{status: :paused})

      assert {:ok, %Survey{status: :active}} =
               Surveys.update_survey(scope, draft, %{status: :active})
    end
  end

  describe "reading surveys" do
    test "lists a site's surveys, active first", %{scope: scope, site: site} do
      _draft = survey_fixture(scope, site, %{question: "Draft"})
      active = survey_fixture(scope, site, %{question: "Active", status: :active})

      assert [first | _rest] = Surveys.list_surveys(scope, site)
      assert first.id == active.id
      assert length(Surveys.list_surveys(scope, site)) == 2
    end

    test "does not leak surveys from another site", %{scope: scope, site: site} do
      survey = survey_fixture(scope, site)
      other_site = site_fixture(scope)

      assert Surveys.list_surveys(scope, other_site) == []

      assert_raise Ecto.NoResultsError, fn ->
        Surveys.get_survey!(scope, other_site, survey.id)
      end
    end

    test "get_active_survey/2 returns the served survey, or nil", %{scope: scope, site: site} do
      assert Surveys.get_active_survey(scope, site) == nil

      active = survey_fixture(scope, site, %{status: :active})
      assert Surveys.get_active_survey(scope, site).id == active.id
    end

    test "refuses another org", %{scope: scope, other_scope: other_scope} do
      other_site = site_fixture(other_scope)
      survey = survey_fixture(other_scope, other_site)

      assert_raise FunctionClauseError, fn -> Surveys.list_surveys(scope, other_site) end
      assert_raise FunctionClauseError, fn -> Surveys.update_survey(scope, survey, %{}) end
    end
  end
end
