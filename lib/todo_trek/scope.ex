defmodule TodoTrek.Scope do
  @moduledoc """
  Defines the scope the caller to be used throughout the app.

  The %Scope{} allows public interfaces to receive information
  about the caller, such as if the call is initiated from an end-user,
  and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope. It is useful
  for logging as well as for scoping pubsub subscriptions and broadcasts when a
  caller subscribes to an interface or performs a particular action.

  Feel free to extend the fields on this struct to fit the needs of the
  growing application requirements.
  """
  defstruct current_user: nil, current_user_id: nil, last_side_effect_at: nil

  def for_user(current_user_or_nil, _connect_params \\ %{}, _session \\ %{})

  def for_user(nil, %{} = _connect_params, %{} = _session) do
    %__MODULE__{current_user: nil, current_user_id: nil}
  end

  def for_user(%TodoTrek.Accounts.User{} = user, %{} = connect_params, %{} = session) do
    last_at_param = connect_params["last_side_effect_at"] || session["last_side_effect_at"]

    last_side_effect_at =
      case last_at_param do
        str when is_binary(str) -> validate_last_side_effect_at(String.to_integer(str))
        int when is_integer(int) -> validate_last_side_effect_at(int)
        _ -> nil
      end

    %__MODULE__{
      current_user: user,
      current_user_id: user.id,
      last_side_effect_at: last_side_effect_at
    }
  end

  defp validate_last_side_effect_at(at) when is_integer(at) do
    now = now_time()

    cond do
      at > now or at <= 0 -> now - 30_000
      now - at > 30_000 -> now - 30_000
      true -> at
    end
  end

  def bump_last_side_effect(%__MODULE__{} = scope) do
    %__MODULE__{scope | last_side_effect_at: now_time()}
  end

  defp now_time, do: System.system_time(:millisecond)
end
