defmodule Bob.Supervisor do
  use Supervisor

  def start_link() do
    :supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    tree = [
      supervisor(Task.Supervisor, [[name: Bob.Tasks]]),
      worker(Bob.Queue, []),
      worker(Bob.Schedule, [])
    ]

    supervise(tree, strategy: :rest_for_one)
  end
end
