defmodule TodoTrekWeb.TodoListComponent do
  use TodoTrekWeb, :live_component

  alias TodoTrek.{Events, Todos}
  alias TodoTrek.Todos.Todo

  def hook(method, opts \\ []) do
    opts = Keyword.put(opts, :detail, %{method: method})
    JS.dispatch("phx:call-hook", opts)
  end

  attr :id, :any, required: true
  attr :insert_into, :string, required: true
  attr :on_activate, JS, default: nil
  attr :on_dismiss, JS, default: nil

  slot :inner_block, required: true
  slot :template, required: true
  attr :rest, :global

  def phx_optimistic_stream(assigns) do
    ~H"""
    <phx-optimistic-stream
      id={@id}
      insert-into={@insert_into}
      on-activate={@on_activate}
      on-dismiss={@on_dismiss}
      {@rest}
    >
      <template><%= render_slot(@template) %></template>
      <%= render_slot(@inner_block) %>
    </phx-optimistic-stream>
    """
  end

  def render(assigns) do
    ~H"""
    <div data-scope>
      <div
        id={"todos-#{@list_id}"}
        phx-update="stream"
        phx-hook="Sortable"
        class="grid grid-cols-1 gap-2"
        data-group="todos"
        data-list_id={@list_id}
      >
        <div
          :for={{id, form} <- @streams.todos}
          id={id}
          data-id={form.data.id}
          data-list_id={form.data.list_id}
          class="
          relative flex items-center space-x-3 rounded-lg border border-gray-300 bg-white px-2 shadow-sm
          focus-within:ring-2 focus-within:ring-indigo-500 focus-within:ring-offset-2 hover:border-gray-400
          drag-item:focus-within:ring-0 drag-item:focus-within:ring-offset-0
          drag-ghost:bg-zinc-300 drag-ghost:border-0 drag-ghost:ring-0
          "
        >
          <.simple_form
            for={form}
            phx-change="validate"
            phx-submit="save"
            phx-value-id={form.data.id}
            phx-target={@myself}
            phx-auto-recover="ignore"
            class="min-w-0 flex-1 drag-ghost:opacity-0"
          >
            <div class="flex">
              <button
                :if={form.data.id}
                type="button"
                phx-click={JS.push("toggle_complete", target: @myself, value: %{id: form.data.id})}
                class="w-10"
              >
                <.icon
                  name="hero-check-circle"
                  class={[
                    "w-7 h-7",
                    if(form[:status].value == :completed,
                      do: "bg-green-600 phx-click-loading:bg-gray-300",
                      else: "bg-gray-300 phx-click-loading:bg-green-600"
                    )
                  ]}
                />
              </button>
              <div class="flex-auto">
                <input type="hidden" name={form[:status].name} value={form[:status].value} />
                <.input
                  type="text"
                  field={form[:title]}
                  border={false}
                  placeholder="New todo..."
                  phx-blur={form.data.id && JS.dispatch("submit", to: "##{form.id}")}
                  phx-target={@myself}
                  class={
                    if(form[:status].value == :completed,
                      do:
                        "line-through text-gray-500 phx-page-loading:text-gray-900 phx-page-loading:no-underline",
                      else:
                        "text-gray-900 phx-page-loading:text-gray-500 phx-page-loading:line-through"
                    )
                  }
                />
              </div>
              <button
                :if={form.data.id}
                type="button"
                phx-click={
                  JS.push("delete", target: @myself, value: %{id: form.data.id}) |> hide("##{id}")
                }
                class="w-10 -mt-1"
              >
                <.icon name="hero-x-mark" />
              </button>
            </div>
          </.simple_form>
        </div>
      </div>

      <.phx_optimistic_stream
        id={"todo-add-#{@list_id}"}
        insert_into={"todos-#{@list_id}"}
        on_dismiss={JS.hide(to: "$form") |> JS.show(to: "$addTodo")}
      >
        <:template>
          <pending-todo class="relative animate-pulse flex items-center space-x-3 rounded-lg border border-gray-300 bg-white px-2 shadow-sm">
            <div class="min-w-0 flex-1">
              <div class="flex">
                <button type="button" class="w-10" disabled>
                  <.icon name="hero-check-circle" class="w-7 h-7 bg-gray-300" />
                </button>
                <div class="flex-auto">
                  <.input type="text" border={false} name="pending" value="" disabled />
                </div>
                <div class="w-10 -mt-1" />
              </div>
            </div>
          </pending-todo>
        </:template>
        <.simple_form
          for={%{}}
          phx-submit="create_todo"
          phx-target={@myself}
          data-ref="form"
          class="hidden relative mt-2 flex items-center space-x-3 rounded-lg border border-gray-300 bg-white px-2 shadow-sm focus-within:ring-2 focus-within:ring-indigo-500 focus-within:ring-offset-2 hover:border-gray-400 drag-item:focus-within:ring-0 drag-item:focus-within:ring-offset-0 drag-ghost:bg-zinc-300 drag-ghost:border-0 drag-ghost:ring-0"
        >
          <.input
            type="text"
            name="title"
            value=""
            placeholder="New todo..."
            errors={[]}
            border={false}
            data-ref="input"
          />
        </.simple_form>
      </.phx_optimistic_stream>

      <.button
        phx-click={
          JS.hide()
          |> JS.show(to: "$form")
          |> JS.focus(to: "$input")
        }
        class="mt-2"
        data-ref="addTodo"
      >
        Add Todo
      </.button>
    </div>
    """
  end

  def update(%{event: %Events.TodoToggled{todo: todo}}, socket) do
    {:ok, stream_insert(socket, :todos, to_change_form(todo, %{}))}
  end

  def update(%{event: %Events.TodoAdded{todo: todo}}, socket) do
    {:ok, stream_insert(socket, :todos, to_change_form(todo, %{}))}
  end

  def update(%{event: %Events.TodoUpdated{todo: todo}}, socket) do
    {:ok, stream_insert(socket, :todos, to_change_form(todo, %{}))}
  end

  def update(%{event: %Events.TodoRepositioned{todo: todo}}, socket) do
    {:ok, stream_insert(socket, :todos, to_change_form(todo, %{}), at: todo.position)}
  end

  def update(%{event: %Events.TodoDeleted{todo: todo}}, socket) do
    {:ok, stream_delete(socket, :todos, to_change_form(todo, %{}))}
  end

  def update(%{list: list} = assigns, socket) do
    todo_forms = Enum.map(list.todos, &to_change_form(&1, %{}))

    {:ok,
     socket
     |> assign_new(:new_form, fn -> to_change_form(build_todo(list.id), %{}) end)
     |> assign(list_id: list.id, scope: assigns.scope)
     |> stream(:todos, todo_forms)}
  end

  def handle_event("validate", %{"todo" => todo_params} = params, socket) do
    todo = %Todo{id: params["id"], list_id: socket.assigns.list_id}

    {:noreply, stream_insert(socket, :todos, to_change_form(todo, todo_params, :validate))}
  end

  def handle_event("save", %{"id" => id, "todo" => params}, socket) do
    todo = Todos.get_todo!(socket.assigns.scope, id)

    case Todos.update_todo(socket.assigns.scope, todo, params) do
      {:ok, updated_todo} ->
        {:noreply, stream_insert(socket, :todos, to_change_form(updated_todo, %{}))}

      {:error, changeset} ->
        {:noreply, stream_insert(socket, :todos, to_change_form(changeset, %{}, :insert))}
    end
  end

  def handle_event("validate_new", %{"todo" => todo_params} = params, socket) do
    todo = %Todo{id: params["id"], list_id: socket.assigns.list_id}

    {:noreply, assign(socket, :new_form, to_change_form(todo, todo_params, :validate))}
  end

  def handle_event("create_todo", params, socket) do
    # Process.sleep(1000)
    list = Todos.get_list!(socket.assigns.scope, socket.assigns.list_id)

    case Todos.create_todo(socket.assigns.scope, list, params) do
      {:ok, new_todo} ->
        {:noreply,
         socket
         |> assign(:new_form, to_change_form(build_todo(socket.assigns.list_id), %{}))
         |> stream_insert(:todos, to_change_form(new_todo, %{}))}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_form, to_change_form(changeset, params, :insert))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    todo = Todos.get_todo!(socket.assigns.scope, id)
    {:ok, todo} = Todos.delete_todo(socket.assigns.scope, todo)
    {:noreply, stream_delete(socket, :todos, to_change_form(todo, %{}))}
  end

  def handle_event("toggle_complete", %{"id" => id}, socket) do
    todo = Todos.get_todo!(socket.assigns.scope, id)
    {:ok, todo} = Todos.toggle_complete(socket.assigns.scope, todo)

    {:noreply, stream_insert(socket, :todos, to_change_form(todo, %{}))}
  end

  def handle_event("reposition", %{"id" => id, "new" => new_idx, "old" => _} = params, socket) do
    case params do
      %{"list_id" => old_list_id, "to" => %{"list_id" => old_list_id}} ->
        todo = Todos.get_todo!(socket.assigns.scope, id)
        Todos.update_todo_position(socket.assigns.scope, todo, new_idx)
        {:noreply, socket}

      %{"list_id" => _old_list_id, "to" => %{"list_id" => new_list_id}} ->
        todo = Todos.get_todo!(socket.assigns.scope, id)
        list = Todos.get_list!(socket.assigns.scope, new_list_id)
        Todos.move_todo_to_list(socket.assigns.scope, todo, list, new_idx)
        {:noreply, socket}
    end
  end

  def handle_event("discard", _params, socket) do
    todo = build_todo(socket.assigns.list_id)
    {:noreply, stream_delete(socket, :todos, to_change_form(todo, %{}))}
  end

  def handle_event("restore_if_unsaved", %{"value" => val} = params, socket) do
    id = params["id"]
    todo = Todos.get_todo!(socket.assigns.scope, id)

    if todo.title == val do
      {:noreply, socket}
    else
      {:noreply, stream_insert(socket, :todos, to_change_form(todo, %{}))}
    end
  end

  defp to_change_form(todo_or_changeset, params, action \\ nil) do
    changeset =
      todo_or_changeset
      |> Todos.change_todo(params)
      |> Map.put(:action, action)

    to_form(changeset, as: "todo", id: "form-#{changeset.data.list_id}-#{changeset.data.id}")
  end

  defp build_todo(list_id), do: %Todo{list_id: list_id}
end
