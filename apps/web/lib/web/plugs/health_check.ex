defmodule Web.Plugs.HealthCheck do
  @moduledoc false

  import Plug.Conn

  def init(opts) do
    path = Keyword.get(opts, :path, "/health")
    [path: path]
  end

  def call(conn = %Plug.Conn{request_path: path}, path: path) do
    conn
    |> send_resp(200, "")
    |> halt()
  end

  def call(conn, _opts), do: conn
end
