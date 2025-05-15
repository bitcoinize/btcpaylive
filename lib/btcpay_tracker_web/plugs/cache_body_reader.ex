defmodule BtcpayTrackerWeb.Plugs.CacheBodyReader do
  import Plug.Conn

  @doc """
  Reads the request body, assigns it to :raw_body in the connection,
  and returns it for Plug.Parsers.
  """
  @spec read_body(Plug.Conn.t(), Plug.opts()) :: {:ok, binary, Plug.Conn.t()} | {:error, any}
  def read_body(conn, opts) do
    {:ok, body, conn_after_read_body} = Plug.Conn.read_body(conn, opts)
    conn_with_raw_body = assign(conn_after_read_body, :raw_body, body)
    {:ok, body, conn_with_raw_body}
  end
end 