defmodule LitenpsWeb.SiteLive.Index do
  use LitenpsWeb, :live_view

  alias Litenps.Sites

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Sites
        <:subtitle>Each site gets its own snippet, origins and keys.</:subtitle>
        <:actions>
          <.button id="new-site" variant="primary" navigate={~p"/sites/new"}>
            <.icon name="hero-plus" class="size-4" /> New site
          </.button>
        </:actions>
      </.header>

      <div id="sites" phx-update="stream" class="mt-6 grid gap-3">
        <div
          id="sites-empty"
          class="hidden only:block rounded-box border border-dashed border-base-300 p-10 text-center"
        >
          <.icon name="hero-globe-alt" class="size-8 opacity-40" />
          <p class="mt-3 font-semibold">No sites yet</p>
          <p class="mt-1 text-sm opacity-70">Create one to get an install snippet.</p>
        </div>
        <.link
          :for={{id, site} <- @streams.sites}
          id={id}
          navigate={~p"/sites/#{site}"}
          class="group flex items-center justify-between gap-4 rounded-box border border-base-300 bg-base-100 px-5 py-4 transition hover:border-primary/50 hover:shadow-sm"
        >
          <div class="min-w-0">
            <p class="truncate font-semibold">{site.name}</p>
            <p class="mt-0.5 truncate text-sm opacity-70">
              <%= if site.allowed_origins == [] do %>
                <span class="text-warning">No origins yet</span>
              <% else %>
                {Enum.join(site.allowed_origins, ", ")}
              <% end %>
            </p>
          </div>
          <.icon
            name="hero-chevron-right"
            class="size-5 shrink-0 opacity-40 transition group-hover:translate-x-0.5 group-hover:opacity-80"
          />
        </.link>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sites")
     |> stream(:sites, Sites.list_sites(socket.assigns.current_scope))}
  end
end
