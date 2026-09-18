defmodule LitenpsWeb.SiteLive.Form do
  use LitenpsWeb, :live_view

  alias Litenps.Sites
  alias Litenps.Sites.Site

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>
          <%= if @live_action == :new do %>
            You can add origins now or later — the snippet waits until you do.
          <% else %>
            Changes apply to the widget straight away.
          <% end %>
        </:subtitle>
      </.header>

      <.form for={@form} id="site-form" phx-change="validate" phx-submit="save" class="mt-6">
        <.input field={@form[:name]} type="text" label="Name" placeholder="Marketing site" />

        <.input
          field={@form[:allowed_origins]}
          type="textarea"
          label="Allowed origins"
          value={origins_text(@form[:allowed_origins].value)}
          placeholder="https://example.com\nhttps://www.example.com"
          rows="4"
          spellcheck="false"
        />
        <p class="-mt-1 mb-3 text-xs opacity-70">
          One per line. The widget only answers pages served from these origins; a bare
          domain is read as <code>https://</code>.
        </p>

        <div class="grid gap-x-4 sm:grid-cols-2">
          <.input
            field={@form[:timezone]}
            type="select"
            label="Timezone"
            options={@timezones}
          />
          <.input
            field={@form[:data_retention_days]}
            type="number"
            label="Keep responses for (days)"
            min="30"
            max="365"
          />
        </div>

        <footer class="mt-4 flex items-center gap-2">
          <.button phx-disable-with="Saving..." variant="primary">Save site</.button>
          <.button navigate={@return_to}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:timezones, Sites.list_timezones())
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    scope = socket.assigns.current_scope
    site = %Site{org_id: scope.org.id}

    socket
    |> assign(:page_title, "New site")
    |> assign(:site, site)
    |> assign(:return_to, ~p"/sites")
    |> assign(:form, to_form(Sites.change_site(scope, site)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope
    site = Sites.get_site!(scope, id)

    socket
    |> assign(:page_title, "Edit #{site.name}")
    |> assign(:site, site)
    |> assign(:return_to, ~p"/sites/#{site}")
    |> assign(:form, to_form(Sites.change_site(scope, site)))
  end

  @impl true
  def handle_event("validate", %{"site" => params}, socket) do
    changeset = Sites.change_site(socket.assigns.current_scope, socket.assigns.site, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"site" => params}, socket) do
    save_site(socket, socket.assigns.live_action, params)
  end

  defp save_site(socket, :new, params) do
    case Sites.create_site(socket.assigns.current_scope, params) do
      {:ok, site} ->
        {:noreply,
         socket
         |> put_flash(:info, "Site created")
         |> push_navigate(to: ~p"/sites/#{site}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_site(socket, :edit, params) do
    case Sites.update_site(socket.assigns.current_scope, socket.assigns.site, params) do
      {:ok, site} ->
        {:noreply,
         socket
         |> put_flash(:info, "Site updated")
         |> push_navigate(to: ~p"/sites/#{site}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # The field holds a list once loaded, and the raw textarea text once edited.
  defp origins_text(origins) when is_list(origins), do: Enum.join(origins, "\n")
  defp origins_text(text), do: text
end
