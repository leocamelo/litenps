defmodule Litenps.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Litenps.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Litenps.Accounts.Org
  alias Litenps.Accounts.User

  defstruct user: nil, org: nil

  @type t :: %__MODULE__{user: User.t() | nil, org: Org.t() | nil}

  @doc """
  Creates a scope for the given user.

  The user's organization must be loaded. A scope without an organization
  cannot scope a query to a tenant, so building one is a programming error
  rather than a value any caller should have to handle.

  Returns nil if no user is given.
  """
  def for_user(%User{org: %Org{} = org} = user) do
    %__MODULE__{user: user, org: org}
  end

  def for_user(%User{} = user) do
    raise ArgumentError, """
    cannot build a scope for user #{user.id} because its organization is not loaded.

    Load users through `Litenps.Accounts`, which preloads the organization on
    every path that feeds a scope.
    """
  end

  def for_user(nil), do: nil
end
