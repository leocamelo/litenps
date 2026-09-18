defmodule LitenpsWeb.SiteLiveTest do
  use LitenpsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Litenps.AccountsFixtures
  import Litenps.SitesFixtures

  alias Litenps.Sites

  test "requires a logged-in user", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/sites")
  end

  describe "index" do
    setup :register_and_log_in_user

    test "shows an empty state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sites")

      assert has_element?(view, "#sites-empty")
    end

    test "lists only the org's sites", %{conn: conn, scope: scope} do
      site = site_fixture(scope, %{name: "Mine"})
      other = site_fixture(org_scope_fixture(), %{name: "Theirs"})

      {:ok, view, _html} = live(conn, ~p"/sites")

      assert has_element?(view, "#sites-#{site.id}", "Mine")
      refute has_element?(view, "#sites-#{other.id}")
    end
  end

  describe "new" do
    setup :register_and_log_in_user

    test "creates a site and lands on it", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/sites/new")

      {:ok, _show, html} =
        view
        |> form("#site-form",
          site: %{
            name: "Shop",
            allowed_origins: "shop.example\nhttps://www.shop.example",
            timezone: "Europe/Lisbon",
            data_retention_days: "90"
          }
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Site created"

      assert [
               %{
                 name: "Shop",
                 allowed_origins: ["https://shop.example", "https://www.shop.example"]
               }
             ] =
               Sites.list_sites(scope)
    end

    test "shows validation errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sites/new")

      html =
        view
        |> form("#site-form", site: %{name: "", allowed_origins: "https://example.com/path"})
        |> render_change()

      assert html =~ "can&#39;t be blank"
      assert html =~ "https://example.com/path is not a valid origin"
    end
  end

  describe "edit" do
    setup :register_and_log_in_user

    test "updates the site", %{conn: conn, scope: scope} do
      site = site_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/sites/#{site}/edit")

      {:ok, _show, html} =
        view
        |> form("#site-form", site: %{name: "Renamed"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Renamed"
    end

    test "cannot open another org's site", %{conn: conn} do
      other = site_fixture(org_scope_fixture())

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/sites/#{other}/edit") end
    end
  end

  describe "show" do
    setup :register_and_log_in_user

    test "asks for origins before showing the snippet", %{conn: conn, scope: scope} do
      site = site_fixture(scope, %{allowed_origins: []})
      {:ok, view, _html} = live(conn, ~p"/sites/#{site}")

      assert has_element?(view, "#snippet-needs-origins")
      refute has_element?(view, "#snippet")
    end

    test "shows the snippet with the site's key", %{conn: conn, scope: scope} do
      site = site_fixture(scope)
      [key] = Sites.list_api_keys(scope, site)
      {:ok, view, _html} = live(conn, ~p"/sites/#{site}")

      assert has_element?(view, "#snippet", "/w.js?k=#{key.key}")
    end

    test "issues a labelled key", %{conn: conn, scope: scope} do
      site = site_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/sites/#{site}")

      view |> form("#key-form", api_key: %{label: "Staging"}) |> render_submit()

      assert [%{label: "Staging"}, _first] = Sites.list_api_keys(scope, site)
      assert has_element?(view, "#keys li", "Staging")
    end

    test "the only active key cannot be revoked", %{conn: conn, scope: scope} do
      site = site_fixture(scope)
      [key] = Sites.list_api_keys(scope, site)
      {:ok, view, _html} = live(conn, ~p"/sites/#{site}")

      assert has_element?(view, "#revoke-#{key.id}[disabled]")
    end

    test "revokes a key once another is active", %{conn: conn, scope: scope} do
      site = site_fixture(scope)
      [old] = Sites.list_api_keys(scope, site)
      {:ok, new} = Sites.create_api_key(scope, site)
      {:ok, view, _html} = live(conn, ~p"/sites/#{site}")

      view |> element("#revoke-#{old.id}") |> render_click()

      refute has_element?(view, "#revoke-#{old.id}")
      assert has_element?(view, "#snippet", new.key)
    end

    test "cannot open another org's site", %{conn: conn} do
      other = site_fixture(org_scope_fixture())

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/sites/#{other}") end
    end
  end
end
