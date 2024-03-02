defmodule MediasoupElixirDemoWeb.RouterGroup do
  def start_link() do
    :pg.start_link(__MODULE__)
  end

  @spec join(any(), pid() | [pid()]) :: :ok
  def join(group, pid_or_pids), do: :pg.join(__MODULE__, group, pid_or_pids)

  @spec leave(any(), pid() | [pid()]) :: :not_joined | :ok
  def leave(group, pid_or_pids), do: :pg.leave(__MODULE__, group, pid_or_pids)

  @spec monitor(any()) :: {reference(), [pid()]}
  def monitor(group), do: :pg.monitor(__MODULE__, group)

  @spec demonitor(reference()) :: false | :ok
  def demonitor(ref), do: :pg.demonitor(__MODULE__, ref)

  @spec get_local_members(any()) :: [pid()]
  def get_local_members(group), do: :pg.get_local_members(__MODULE__, group)

  @spec get_members(any()) :: [pid()]
  def get_members(group), do: :pg.get_members(__MODULE__, group)

  @spec which_groups() :: list()
  def which_groups(), do: :pg.which_groups(__MODULE__)

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    }
  end
end
