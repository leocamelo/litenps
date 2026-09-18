defmodule LitenpsWeb.LayoutsTest do
  use LitenpsWeb.ConnCase, async: true

  describe "navbar" do
    test "offers log in and register to a visitor", %{conn: conn} do
      doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

      assert nav_links(doc) == ["/", "/users/log-in", "/users/register"]
    end

    test "offers the dashboard and account links to a logged-in user on the home page",
         %{conn: conn} do
      %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
      doc = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

      assert nav_links(doc) == ["/sites", "/sites", "/users/settings", "/users/log-out"]
      assert LazyHTML.text(LazyHTML.query(doc, "#navbar")) =~ user.email
    end

    test "is rendered once on a dashboard page, root layout included", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      doc = conn |> get(~p"/sites") |> html_response(200) |> LazyHTML.from_document()

      assert doc |> LazyHTML.query("#navbar") |> Enum.count() == 1
      assert doc |> LazyHTML.query("a[href='/users/log-out']") |> Enum.count() == 1
    end
  end

  defp nav_links(doc) do
    doc |> LazyHTML.query("#navbar a") |> LazyHTML.attribute("href")
  end
end
