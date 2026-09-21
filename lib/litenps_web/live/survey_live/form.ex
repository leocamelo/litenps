defmodule LitenpsWeb.SurveyLive.Form do
  use LitenpsWeb, :live_view

  alias Litenps.Sites
  alias Litenps.Surveys
  alias Litenps.Surveys.Survey

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>On {@site.name}</:subtitle>
      </.header>

      <.form for={@form} id="survey-form" phx-change="validate" phx-submit="save" class="mt-6">
        <.input
          field={@form[:question]}
          type="text"
          label="Question"
          placeholder="How likely are you to recommend us to a friend?"
        />
        <.input
          field={@form[:followup_question]}
          type="text"
          label="Follow-up question"
          placeholder="What is the main reason for your score?"
        />
        <p class="-mt-1 mb-3 text-xs opacity-70">Asked after the score. Leave blank to skip it.</p>

        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={Enum.map(Survey.statuses(), &{String.capitalize(to_string(&1)), &1})}
        />
        <p class="-mt-1 mb-3 text-xs opacity-70">
          Only one survey per site can be active. Drafts and paused surveys are never served.
        </p>

        <fieldset class="mt-6 rounded-box border border-base-300 p-4">
          <legend class="px-2 text-sm font-semibold">Who sees it</legend>

          <.inputs_for :let={targeting} field={@form[:targeting]}>
            <.input
              field={targeting[:url_patterns]}
              type="textarea"
              label="Page paths"
              value={patterns_text(targeting[:url_patterns].value)}
              placeholder="/pricing*\n/checkout*"
              rows="3"
              spellcheck="false"
            />
            <p class="-mt-1 mb-3 text-xs opacity-70">
              One per line, <code>*</code> matches anything. Leave blank for every page.
            </p>

            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input
                field={targeting[:delay_seconds]}
                type="number"
                label="Delay (seconds)"
                min="0"
                max="300"
              />
              <.input
                field={targeting[:device]}
                type="select"
                label="Devices"
                options={[{"All devices", :all}, {"Desktop only", :desktop}, {"Mobile only", :mobile}]}
              />
            </div>
          </.inputs_for>

          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input
              field={@form[:cooldown_days]}
              type="number"
              label="Ask again after (days)"
              min="1"
              max="365"
            />
            <.input
              field={@form[:sample_rate]}
              type="number"
              label="Share of visitors"
              min="0.05"
              max="1"
              step="0.05"
            />
          </div>
          <p class="-mt-1 text-xs opacity-70">
            1 asks everyone who matches; 0.25 asks a quarter of them.
          </p>
        </fieldset>

        <footer class="mt-4 flex items-center gap-2">
          <.button phx-disable-with="Saving..." variant="primary">Save survey</.button>
          <.button navigate={~p"/sites/#{@site}"}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"site_id" => site_id} = params, _session, socket) do
    scope = socket.assigns.current_scope
    site = Sites.get_site!(scope, site_id)

    {:ok, socket |> assign(:site, site) |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    %{current_scope: scope, site: site} = socket.assigns
    survey = %Survey{org_id: scope.org.id, site_id: site.id}

    socket
    |> assign(:page_title, "New survey")
    |> assign(:survey, survey)
    |> assign(:form, to_form(Surveys.change_survey(scope, survey)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    %{current_scope: scope, site: site} = socket.assigns
    survey = Surveys.get_survey!(scope, site, id)

    socket
    |> assign(:page_title, "Edit survey")
    |> assign(:survey, survey)
    |> assign(:form, to_form(Surveys.change_survey(scope, survey)))
  end

  @impl true
  def handle_event("validate", %{"survey" => params}, socket) do
    changeset = Surveys.change_survey(socket.assigns.current_scope, socket.assigns.survey, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"survey" => params}, socket) do
    save_survey(socket, socket.assigns.live_action, params)
  end

  defp save_survey(socket, :new, params) do
    %{current_scope: scope, site: site} = socket.assigns

    case Surveys.create_survey(scope, site, params) do
      {:ok, _survey} ->
        {:noreply,
         socket
         |> put_flash(:info, "Survey created")
         |> push_navigate(to: ~p"/sites/#{site}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_survey(socket, :edit, params) do
    %{current_scope: scope, site: site, survey: survey} = socket.assigns

    case Surveys.update_survey(scope, survey, params) do
      {:ok, _survey} ->
        {:noreply,
         socket
         |> put_flash(:info, "Survey updated")
         |> push_navigate(to: ~p"/sites/#{site}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # The field holds a list once loaded, and the raw textarea text once edited.
  defp patterns_text(patterns) when is_list(patterns), do: Enum.join(patterns, "\n")
  defp patterns_text(text), do: text
end
