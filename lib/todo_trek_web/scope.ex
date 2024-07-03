defmodule TodoTrekWeb.Scope do
  import Phoenix.Component

  def on_mount(:default, _params, session, socket) do
    connect_params = Phoenix.LiveView.get_connect_params(socket) || %{}
    current_user = socket.assigns[:current_user]
    scope = TodoTrek.Scope.for_user(current_user, connect_params, session)
    new_socket = assign(socket, :scope, scope)

    {:cont, new_socket}
  end

  def register_side_effects(socket, events, info_match \\ nil) do
    socket =
      socket
      |> Phoenix.LiveView.attach_hook(:side_effects, :handle_event, fn event, _params, socket ->
        if event in events, do: send(self(), {__MODULE__, :bump})
        {:cont, socket}
      end)

    if socket.assigns[:myself] do
      socket
    else
      Phoenix.LiveView.attach_hook(socket, :side_effects_bump, :handle_info, fn
        {__MODULE__, :bump}, socket ->
          {:halt, bump_last_side_effect(socket)}

        msg, socket ->
          if info_match && info_match.(msg) do
            {:cont, bump_last_side_effect(socket)}
          else
            {:cont, socket}
          end
      end)
    end
  end

  defp bump_last_side_effect(socket) do
    new_scope = TodoTrek.Scope.bump_last_side_effect(socket.assigns.scope)

    socket
    |> assign(scope: new_scope)
    |> Phoenix.LiveView.push_event("last_side_effect", %{at: new_scope.last_side_effect_at})
  end
end
