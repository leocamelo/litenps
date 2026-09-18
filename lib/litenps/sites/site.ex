defmodule Litenps.Sites.Site do
  @moduledoc """
  A site is what a customer measures: one embed, one set of allowed origins, one
  timezone for bucketing days. An org has many sites.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Litenps.Accounts.Org
  alias Litenps.Sites.ApiKey

  @min_retention_days 30
  @max_retention_days 365
  @max_origins 20

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "sites" do
    field :name, :string
    field :allowed_origins, {:array, :string}, default: []
    field :timezone, :string, default: "Etc/UTC"
    field :data_retention_days, :integer, default: 90

    belongs_to :org, Org
    has_many :api_keys, ApiKey

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for creating or editing a site.

  `allowed_origins` may be empty, so a site can be created before its origins
  are known. The widget endpoints fail closed: a site without origins accepts no
  widget requests.

  `allowed_origins` accepts a list, or a single string of origins separated by
  whitespace or commas, as a textarea submits it. Each origin is normalized to
  `scheme://host[:port]`; a bare host is assumed to be `https`.

  Timezone names are validated by `Litenps.Sites` against the database, which is
  also where day bucketing happens.
  """
  def changeset(site, attrs) do
    site
    |> cast(split_origin_text(attrs), [:name, :allowed_origins, :timezone, :data_retention_days])
    |> validate_required([:name, :timezone, :data_retention_days])
    |> validate_length(:name, max: 160)
    |> validate_number(:data_retention_days,
      greater_than_or_equal_to: @min_retention_days,
      less_than_or_equal_to: @max_retention_days
    )
    |> normalize_origins()
    |> validate_length(:allowed_origins, max: @max_origins)
  end

  defp split_origin_text(attrs) do
    Map.new(attrs, fn
      {key, value} when key in ["allowed_origins", :allowed_origins] and is_binary(value) ->
        {key, String.split(value, ~r/[\s,]+/, trim: true)}

      pair ->
        pair
    end)
  end

  defp normalize_origins(changeset) do
    case fetch_change(changeset, :allowed_origins) do
      {:ok, origins} ->
        {valid, invalid} =
          origins
          |> Enum.map(&{&1, normalize_origin(&1)})
          |> Enum.split_with(fn {_input, result} -> match?({:ok, _}, result) end)

        changeset =
          put_change(
            changeset,
            :allowed_origins,
            valid |> Enum.map(fn {_, {:ok, o}} -> o end) |> Enum.uniq()
          )

        Enum.reduce(invalid, changeset, fn {input, :error}, acc ->
          add_error(acc, :allowed_origins, "%{origin} is not a valid origin", origin: input)
        end)

      :error ->
        changeset
    end
  end

  @doc """
  Normalizes a single origin to `scheme://host[:port]`, or returns `:error`.

  Paths, queries, fragments, credentials and wildcards are rejected rather than
  stripped, so a pasted URL never silently becomes a broader origin than intended.
  """
  def normalize_origin(input) when is_binary(input) do
    input = input |> String.trim() |> String.downcase()
    input = if String.contains?(input, "://"), do: input, else: "https://" <> input

    with %URI{scheme: scheme, host: host, port: port} = uri when scheme in ["http", "https"] <-
           URI.parse(input),
         true <- valid_host?(host),
         true <- uri.path in [nil, "", "/"],
         true <- is_nil(uri.query) and is_nil(uri.fragment) and is_nil(uri.userinfo) do
      {:ok, format_origin(scheme, host, port)}
    else
      _ -> :error
    end
  end

  defp valid_host?(host) when is_binary(host),
    do: Regex.match?(~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/, host)

  defp valid_host?(_host), do: false

  defp format_origin(scheme, host, port) do
    if port == URI.default_port(scheme),
      do: "#{scheme}://#{host}",
      else: "#{scheme}://#{host}:#{port}"
  end
end
