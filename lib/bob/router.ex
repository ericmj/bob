defmodule Bob.Router do
  use Plug.Router
  use Bob.Plug.Rollbax

  import Plug.Conn

  def call(conn, opts) do
    Bob.Plug.Exception.call(conn, fun: &super(&1, opts))
  end

  plug(Bob.Plug.Forwarded)
  plug(Bob.Plug.Status)
  # TODO: SSL?
  plug(:secret)
  plug(Plug.Parsers, pass: ["application/vnd.bob+erlang"], parsers: [Bob.Plug.Parser])
  plug(:match)
  plug(:dispatch)

  post "dequeue" do
    jobs =
      Enum.reduce(conn.params[:jobs], %{}, fn module, map ->
        case Bob.Queue.dequeue(module) do
          {:ok, args} -> Map.put(map, module, args)
          :error -> map
        end
      end)

    send_resp(conn, 200, Bob.Plug.ErlangFormat.encode_to_iodata!(%{jobs: jobs}))
  end

  defp secret(conn, _opts) do
    secret = Application.get_env(:bob, :agent_secret)

    if get_req_header(conn, "authorization") == [secret] do
      conn
    else
      conn
      |> send_resp(401, "")
      |> halt()
    end
  end
end
