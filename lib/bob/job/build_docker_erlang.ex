defmodule Bob.Job.BuildDockerErlang do
  require Logger

  @alpine "3.11.2"

  def run([ref]) do
    directory = Bob.Directory.new()
    Logger.info("Using directory #{directory}")
    Bob.Script.run({:script, "docker/erlang.sh"}, [ref, @alpine], directory)
  end

  def equal?(args, args), do: true
  def equal?(_, _), do: false

  def similar?(args, args), do: true
  def similar?(_, _), do: false
end
