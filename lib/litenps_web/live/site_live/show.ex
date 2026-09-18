defmodule LitenpsWeb.SiteLive.Show do
  use LitenpsWeb, :live_view

  alias Litenps.Sites
  alias Litenps.Sites.ApiKey

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@site.name}
        <:subtitle>
          {@site.timezone} · responses kept {@site.data_retention_days} days
        </:subtitle>
        <:actions>
          <.button navigate={~p"/sites"}>
            <.icon name="hero-arrow-left" class="size-4" />
          </.button>
          <.button id="edit-site" variant="primary" navigate={~p"/sites/#{@site}/edit"}>
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:actions>
      </.header>

      <section id="install" class="mt-8">
        <h2 class="text-sm font-semibold uppercase tracking-wide opacity-70">Install</h2>

        <%= cond do %>
          <% @site.allowed_origins == [] -> %>
            <div
              id="snippet-needs-origins"
              class="mt-3 flex items-start gap-3 rounded-box border border-warning/40 bg-warning/10 p-4"
            >
              <.icon name="hero-exclamation-triangle" class="mt-0.5 size-5 shrink-0 text-warning" />
              <div class="text-sm">
                <p class="font-semibold">Add an origin to get your snippet</p>
                <p class="mt-1 opacity-80">
                  The widget only answers pages served from an allowed origin, so without
                  one it would stay silent on every page.
                </p>
                <.link
                  id="add-origins"
                  navigate={~p"/sites/#{@site}/edit"}
                  class="mt-2 inline-block font-semibold text-primary hover:underline"
                >
                  Add origins &rarr;
                </.link>
              </div>
            </div>
          <% @snippet_key -> %>
            <p class="mt-2 text-sm opacity-70">
              Paste this before <code>&lt;/body&gt;</code>
              on pages served from {Enum.join(@site.allowed_origins, ", ")}.
            </p>
            <div class="relative mt-3">
              <pre
                id="snippet"
                class="overflow-x-auto rounded-box bg-base-300 p-4 pr-24 text-sm"
              ><code>{snippet(@snippet_key)}</code></pre>
              <.copy_button
                id="copy-snippet"
                value={snippet(@snippet_key)}
                class="absolute right-2 top-2"
              />
            </div>
          <% true -> %>
            <p id="snippet-needs-key" class="mt-3 text-sm opacity-70">
              No active key. Issue one below to get your snippet.
            </p>
        <% end %>
      </section>

      <section id="keys-section" class="mt-10">
        <div class="flex items-end justify-between gap-4">
          <div>
            <h2 class="text-sm font-semibold uppercase tracking-wide opacity-70">Public keys</h2>
            <p class="mt-1 text-sm opacity-70">
              To rotate: issue a new key, update your snippet, then revoke the old one.
            </p>
          </div>
        </div>

        <.form
          for={@key_form}
          id="key-form"
          phx-submit="create_key"
          class="mt-4 flex items-start gap-2"
        >
          <div class="flex-1">
            <.input
              field={@key_form[:label]}
              type="text"
              placeholder="Label (optional), e.g. Staging"
            />
          </div>
          <.button phx-disable-with="Issuing...">
            <.icon name="hero-key" class="size-4" /> Issue key
          </.button>
        </.form>

        <ul
          id="keys"
          phx-update="stream"
          class="mt-2 divide-y divide-base-300 rounded-box border border-base-300"
        >
          <li
            :for={{id, key} <- @streams.keys}
            id={id}
            class={["flex items-center gap-4 px-4 py-3", !ApiKey.active?(key) && "opacity-50"]}
          >
            <div class="min-w-0 flex-1">
              <p class="flex items-center gap-2">
                <span class="font-medium">{key.label || "Unlabeled"}</span>
                <span :if={!ApiKey.active?(key)} class="badge badge-sm">Revoked</span>
              </p>
              <p class="mt-0.5 truncate font-mono text-xs opacity-70">{key.key}</p>
            </div>
            <%= if ApiKey.active?(key) do %>
              <.copy_button id={"copy-#{key.id}"} value={key.key} />
              <button
                id={"revoke-#{key.id}"}
                type="button"
                phx-click="revoke_key"
                phx-value-id={key.id}
                disabled={@active_key_count <= 1}
                title={@active_key_count <= 1 && "Issue another key before revoking this one"}
                data-confirm="Revoke this key? Pages still using it will stop showing the survey."
                class="btn btn-ghost btn-sm text-error disabled:bg-transparent"
              >
                Revoke
              </button>
            <% else %>
              <span class="text-xs opacity-70">
                Revoked {Calendar.strftime(key.revoked_at, "%b %-d, %Y")}
              </span>
            <% end %>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :value, :string, required: true
  attr :class, :any, default: nil

  defp copy_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-hook=".Copy"
      data-value={@value}
      class={["btn btn-ghost btn-sm", @class]}
    >
      <.icon name="hero-clipboard" class="size-4" />
      <span data-label>Copy</span>
    </button>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Copy">
      export default {
        mounted() {
          this.el.addEventListener("click", () => {
            navigator.clipboard.writeText(this.el.dataset.value).then(() => {
              const label = this.el.querySelector("[data-label]")
              label.textContent = "Copied"
              clearTimeout(this.timer)
              this.timer = setTimeout(() => { label.textContent = "Copy" }, 1500)
            })
          })
        }
      }
    </script>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    site = Sites.get_site!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:page_title, site.name)
     |> assign(:site, site)
     |> assign(:key_form, to_form(%{"label" => ""}, as: :api_key))
     |> load_keys()}
  end

  @impl true
  def handle_event("create_key", %{"api_key" => params}, socket) do
    %{current_scope: scope, site: site} = socket.assigns

    case Sites.create_api_key(scope, site, params) do
      {:ok, _key} ->
        {:noreply,
         socket
         |> put_flash(:info, "Key issued")
         |> assign(:key_form, to_form(%{"label" => ""}, as: :api_key))
         |> load_keys()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :key_form, to_form(changeset, as: :api_key))}
    end
  end

  def handle_event("revoke_key", %{"id" => id}, socket) do
    %{current_scope: scope, site: site} = socket.assigns
    key = Sites.get_api_key!(scope, site, id)

    case Sites.revoke_api_key(scope, key) do
      {:ok, _key} ->
        {:noreply, socket |> put_flash(:info, "Key revoked") |> load_keys()}

      {:error, :last_active_key} ->
        {:noreply, put_flash(socket, :error, "Issue another key before revoking this one.")}

      {:error, :already_revoked} ->
        {:noreply, load_keys(socket)}
    end
  end

  # Keys are few per site, and revoking or issuing one changes the snippet and
  # which revoke buttons are enabled, so the whole list is re-read and re-streamed.
  defp load_keys(socket) do
    keys = Sites.list_api_keys(socket.assigns.current_scope, socket.assigns.site)
    active = Enum.filter(keys, &ApiKey.active?/1)

    socket
    |> assign(:snippet_key, List.first(active))
    |> assign(:active_key_count, length(active))
    |> stream(:keys, keys, reset: true)
  end

  # `/w.js` is served from Phase 3, so it is not a verified route yet.
  defp snippet(%ApiKey{key: key}) do
    src = LitenpsWeb.Endpoint.url() <> "/w.js?" <> URI.encode_query(k: key)
    ~s(<script async src="#{src}"></script>)
  end
end
