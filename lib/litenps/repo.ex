defmodule Litenps.Repo do
  use Ecto.Repo,
    otp_app: :litenps,
    adapter: Ecto.Adapters.Postgres
end
