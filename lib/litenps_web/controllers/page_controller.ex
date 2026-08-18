defmodule LitenpsWeb.PageController do
  use LitenpsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
