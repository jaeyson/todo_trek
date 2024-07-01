defmodule TodoTrekWeb.Scope do
  import Phoenix.Component

  def on_mount(:default, _params, session, socket) do
    connect_params = Phoenix.LiveView.get_connect_params(socket) || %{}
    current_user = socket.assigns[:current_user]
    scope = TodoTrek.Scope.for_user(current_user, connect_params, session)
    new_socket = assign(socket, :scope, scope)

    {:cont, attach_side_effect_watcher(new_socket)}
  end

  def bump_last_side_effect(socket) do
    new_scope = TodoTrek.Scope.bump_last_side_effect(socket.assigns.scope)

    socket
    |> assign(scope: new_scope)
    |> Phoenix.LiveView.push_event("last_side_effect", %{at: new_scope.last_side_effect_at})
  end

  def attach_side_effect_watcher(socket) do
    socket =
      socket
      |> Phoenix.LiveView.attach_hook(:side_effects, :handle_event, fn
        _event, _params, socket ->
          send(self(), {__MODULE__, :bump})
          {:cont, socket}
      end)

    if socket.assigns[:myself] do
      socket
    else
      Phoenix.LiveView.attach_hook(socket, :side_effects_bump, :handle_info, fn
        {__MODULE__, :bump}, socket -> {:halt, bump_last_side_effect(socket)}
        _msg, socket -> {:cont, socket}
      end)
    end
  end
end
