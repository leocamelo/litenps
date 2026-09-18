defmodule Litenps.SitesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Litenps.Sites` context.
  """

  alias Litenps.Sites

  def valid_site_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Site #{System.unique_integer([:positive])}",
      allowed_origins: ["https://example.com"],
      timezone: "Europe/Lisbon",
      data_retention_days: 365
    })
  end

  def site_fixture(scope, attrs \\ %{}) do
    {:ok, site} = Sites.create_site(scope, valid_site_attributes(attrs))
    site
  end
end
