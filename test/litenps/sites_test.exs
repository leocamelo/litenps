defmodule Litenps.SitesTest do
  use Litenps.DataCase, async: true

  import Litenps.AccountsFixtures
  import Litenps.SitesFixtures

  alias Litenps.Sites
  alias Litenps.Sites.{ApiKey, Site}

  setup do
    %{scope: org_scope_fixture(), other_scope: org_scope_fixture()}
  end

  describe "list_sites/1" do
    test "returns only the scope's org's sites", %{scope: scope, other_scope: other_scope} do
      site = site_fixture(scope)
      _other = site_fixture(other_scope)

      assert [%Site{id: id}] = Sites.list_sites(scope)
      assert id == site.id
    end
  end

  describe "get_site!/2" do
    test "returns the site", %{scope: scope} do
      site = site_fixture(scope)
      assert Sites.get_site!(scope, site.id).id == site.id
    end

    test "raises for another org's site", %{scope: scope, other_scope: other_scope} do
      site = site_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn -> Sites.get_site!(scope, site.id) end
    end
  end

  describe "create_site/2" do
    test "creates a site in the scope's org with one active key", %{scope: scope} do
      assert {:ok, site} = Sites.create_site(scope, valid_site_attributes())

      assert site.org_id == scope.org.id

      assert [%ApiKey{key: "pk_live_" <> _, revoked_at: nil} = key] =
               Sites.list_api_keys(scope, site)

      assert key.org_id == scope.org.id
    end

    test "ignores an org_id in the attributes", %{scope: scope, other_scope: other_scope} do
      attrs = valid_site_attributes(%{org_id: other_scope.org.id})

      assert {:ok, site} = Sites.create_site(scope, attrs)
      assert site.org_id == scope.org.id
    end

    test "defaults timezone and retention", %{scope: scope} do
      {:ok, site} = Sites.create_site(scope, %{name: "Shop"})

      assert site.timezone == "Etc/UTC"
      assert site.data_retention_days == 90
    end

    test "requires a name", %{scope: scope} do
      {:error, changeset} = Sites.create_site(scope, %{name: ""})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "allows a site with no origins yet", %{scope: scope} do
      assert {:ok, %Site{allowed_origins: []}} =
               Sites.create_site(scope, valid_site_attributes(%{allowed_origins: []}))
    end

    test "rejects an unknown timezone", %{scope: scope} do
      {:error, changeset} =
        Sites.create_site(scope, valid_site_attributes(%{timezone: "Mars/Olympus_Mons"}))

      assert %{timezone: ["is not a known timezone"]} = errors_on(changeset)
    end

    test "bounds retention", %{scope: scope} do
      for days <- [0, 29, 366] do
        {:error, changeset} =
          Sites.create_site(scope, valid_site_attributes(%{data_retention_days: days}))

        assert %{data_retention_days: [_]} = errors_on(changeset)
      end
    end

    test "creates no key when the site is invalid", %{scope: scope} do
      {:error, _changeset} = Sites.create_site(scope, %{name: ""})

      assert Repo.aggregate(ApiKey, :count) == 0
    end
  end

  describe "allowed origins" do
    test "are normalized", %{scope: scope} do
      {:ok, site} =
        Sites.create_site(
          scope,
          valid_site_attributes(%{
            allowed_origins: [
              "Example.com",
              "https://example.com/",
              "https://example.com:443",
              "http://localhost:4000",
              "https://shop.example.com:8443"
            ]
          })
        )

      assert site.allowed_origins == [
               "https://example.com",
               "http://localhost:4000",
               "https://shop.example.com:8443"
             ]
    end

    test "accept text separated by newlines and commas, as a textarea sends it", %{scope: scope} do
      {:ok, site} =
        Sites.create_site(
          scope,
          %{
            "name" => "Shop",
            "allowed_origins" => "https://a.example\n b.example, https://c.example\r\n"
          }
        )

      assert site.allowed_origins == [
               "https://a.example",
               "https://b.example",
               "https://c.example"
             ]
    end

    test "reject anything broader or stranger than an origin", %{scope: scope} do
      for bad <- [
            "https://example.com/path",
            "https://example.com?q=1",
            "https://example.com#top",
            "https://user:pass@example.com",
            "*.example.com",
            "ftp://example.com",
            "https://"
          ] do
        {:error, changeset} =
          Sites.create_site(scope, valid_site_attributes(%{allowed_origins: [bad]}))

        assert "#{bad} is not a valid origin" in errors_on(changeset).allowed_origins
      end
    end
  end

  describe "update_site/3" do
    test "updates the site", %{scope: scope} do
      site = site_fixture(scope)

      assert {:ok, site} = Sites.update_site(scope, site, %{name: "Renamed"})
      assert site.name == "Renamed"
    end

    test "refuses another org's site", %{scope: scope, other_scope: other_scope} do
      site = site_fixture(other_scope)

      assert_raise FunctionClauseError, fn -> Sites.update_site(scope, site, %{name: "Mine"}) end
    end
  end

  describe "change_site/3" do
    test "returns a changeset for a new site built in the scope's org", %{scope: scope} do
      assert %Ecto.Changeset{} = Sites.change_site(scope, %Site{org_id: scope.org.id})
    end
  end

  describe "list_timezones/0" do
    test "lists IANA names without the posix/right duplicates" do
      timezones = Sites.list_timezones()

      assert "Europe/Lisbon" in timezones
      assert "Etc/UTC" in timezones
      refute Enum.any?(timezones, &String.starts_with?(&1, ["posix/", "right/"]))
    end
  end

  describe "api keys" do
    test "any number of keys can be issued, with an optional label", %{scope: scope} do
      site = site_fixture(scope)

      assert {:ok, %ApiKey{label: "Staging"}} =
               Sites.create_api_key(scope, site, %{"label" => "  Staging "})

      assert {:ok, %ApiKey{label: nil}} = Sites.create_api_key(scope, site)
      assert {:ok, %ApiKey{}} = Sites.create_api_key(scope, site)
      assert length(Sites.list_api_keys(scope, site)) == 4
    end

    test "get_api_key!/3 only finds keys of the given site", %{scope: scope} do
      site = site_fixture(scope)
      other_site = site_fixture(scope)
      [key] = Sites.list_api_keys(scope, site)

      assert Sites.get_api_key!(scope, site, key.id).id == key.id
      assert_raise Ecto.NoResultsError, fn -> Sites.get_api_key!(scope, other_site, key.id) end
    end

    test "labels are bounded", %{scope: scope} do
      site = site_fixture(scope)

      assert {:error, changeset} =
               Sites.create_api_key(scope, site, %{label: String.duplicate("x", 61)})

      assert %{label: [_]} = errors_on(changeset)
    end

    test "rotation: issue a new key, then revoke the old one", %{scope: scope} do
      site = site_fixture(scope)
      [old] = Sites.list_api_keys(scope, site)

      {:ok, new} = Sites.create_api_key(scope, site)
      assert {:ok, %ApiKey{revoked_at: %DateTime{}}} = Sites.revoke_api_key(scope, old)

      assert [active] = scope |> Sites.list_api_keys(site) |> Enum.filter(&ApiKey.active?/1)
      assert active.id == new.id
    end

    test "the last active key cannot be revoked", %{scope: scope} do
      site = site_fixture(scope)
      [key] = Sites.list_api_keys(scope, site)

      assert {:error, :last_active_key} = Sites.revoke_api_key(scope, key)
    end

    test "a revoked key cannot be revoked again", %{scope: scope} do
      site = site_fixture(scope)
      [old] = Sites.list_api_keys(scope, site)
      {:ok, _new} = Sites.create_api_key(scope, site)
      {:ok, revoked} = Sites.revoke_api_key(scope, old)

      assert {:error, :already_revoked} = Sites.revoke_api_key(scope, revoked)
    end

    test "another org's key or site is refused", %{scope: scope, other_scope: other_scope} do
      site = site_fixture(other_scope)
      [key] = Sites.list_api_keys(other_scope, site)

      assert_raise FunctionClauseError, fn -> Sites.list_api_keys(scope, site) end
      assert_raise FunctionClauseError, fn -> Sites.create_api_key(scope, site) end
      assert_raise FunctionClauseError, fn -> Sites.revoke_api_key(scope, key) end
    end

    test "the database rejects a key whose org disagrees with its site's",
         %{scope: scope, other_scope: other_scope} do
      site = site_fixture(scope)

      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%ApiKey{site_id: site.id, org_id: other_scope.org.id, key: "pk_live_forged"})
      end
    end
  end
end
