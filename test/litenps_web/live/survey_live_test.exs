defmodule LitenpsWeb.SurveyLiveTest do
  use LitenpsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Litenps.AccountsFixtures
  import Litenps.SitesFixtures
  import Litenps.SurveysFixtures

  alias Litenps.Surveys

  setup :register_and_log_in_user

  setup %{scope: scope} do
    %{site: site_fixture(scope)}
  end

  describe "site page" do
    test "shows an empty state until a survey exists", %{conn: conn, site: site} do
      {:ok, view, _html} = live(conn, ~p"/sites/#{site}")

      assert has_element?(view, "#surveys-empty")
    end

    test "lists the site's surveys", %{conn: conn, scope: scope, site: site} do
      survey = survey_fixture(scope, site, %{question: "Would you recommend us?"})

      {:ok, view, _html} = live(conn, ~p"/sites/#{site}")

      assert has_element?(view, "#surveys-#{survey.id}", "Would you recommend us?")
    end

    test "activates and pauses a survey", %{conn: conn, scope: scope, site: site} do
      survey = survey_fixture(scope, site)
      {:ok, view, _html} = live(conn, ~p"/sites/#{site}")

      view |> element("#activate-#{survey.id}") |> render_click()
      assert Surveys.get_active_survey(scope, site).id == survey.id

      view |> element("#pause-#{survey.id}") |> render_click()
      assert Surveys.get_active_survey(scope, site) == nil
    end

    test "explains why a second survey cannot be activated", %{
      conn: conn,
      scope: scope,
      site: site
    } do
      survey_fixture(scope, site, %{status: :active})
      second = survey_fixture(scope, site)

      {:ok, view, _html} = live(conn, ~p"/sites/#{site}")

      html = view |> element("#activate-#{second.id}") |> render_click()

      assert html =~ "another survey is already active on this site"
      assert Surveys.get_active_survey(scope, site).id != second.id
    end
  end

  describe "new" do
    test "creates a survey with targeting", %{conn: conn, scope: scope, site: site} do
      {:ok, view, _html} = live(conn, ~p"/sites/#{site}/surveys/new")

      {:ok, _show, html} =
        view
        |> form("#survey-form",
          survey: %{
            question: "How likely are you to recommend us?",
            followup_question: "Why?",
            status: "active",
            cooldown_days: "60",
            sample_rate: "0.5",
            targeting: %{
              url_patterns: "/pricing*\n/checkout*",
              delay_seconds: "10",
              device: "mobile"
            }
          }
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Survey created"

      assert [survey] = Surveys.list_surveys(scope, site)
      assert survey.status == :active
      assert survey.cooldown_days == 60
      assert survey.sample_rate == 0.5
      assert survey.targeting.url_patterns == ["/pricing*", "/checkout*"]
      assert survey.targeting.delay_seconds == 10
      assert survey.targeting.device == :mobile
    end

    test "shows validation errors", %{conn: conn, site: site} do
      {:ok, view, _html} = live(conn, ~p"/sites/#{site}/surveys/new")

      html =
        view
        |> form("#survey-form", survey: %{question: "", targeting: %{delay_seconds: "999"}})
        |> render_change()

      assert html =~ "can&#39;t be blank"
      assert html =~ "must be less than or equal to 300"
    end

    test "cannot reach another org's site", %{conn: conn} do
      other_site = site_fixture(org_scope_fixture())

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/sites/#{other_site}/surveys/new") end
    end
  end

  describe "edit" do
    test "updates a survey", %{conn: conn, scope: scope, site: site} do
      survey = survey_fixture(scope, site)
      {:ok, view, _html} = live(conn, ~p"/sites/#{site}/surveys/#{survey}/edit")

      {:ok, _show, html} =
        view
        |> form("#survey-form", survey: %{question: "Renamed question"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Survey updated"
      assert Surveys.get_survey!(scope, site, survey.id).question == "Renamed question"
    end

    test "keeps existing targeting when it is not edited", %{conn: conn, scope: scope, site: site} do
      survey =
        survey_fixture(scope, site, %{
          targeting: %{"url_patterns" => "/pricing*", "device" => "desktop"}
        })

      {:ok, view, _html} = live(conn, ~p"/sites/#{site}/surveys/#{survey}/edit")

      view |> form("#survey-form", survey: %{question: "Still targeted"}) |> render_submit()

      survey = Surveys.get_survey!(scope, site, survey.id)
      assert survey.targeting.url_patterns == ["/pricing*"]
      assert survey.targeting.device == :desktop
    end

    test "cannot open another site's survey", %{conn: conn, scope: scope, site: site} do
      survey = survey_fixture(scope, site)
      other_site = site_fixture(scope)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/sites/#{other_site}/surveys/#{survey}/edit")
      end
    end
  end
end
