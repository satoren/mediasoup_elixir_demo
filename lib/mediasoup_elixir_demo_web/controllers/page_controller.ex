defmodule MediasoupElixirDemoWeb.PageController do
  use MediasoupElixirDemoWeb, :controller

  def home(conn, _params) do
    conn
    |> html(File.read!("priv/static/index.html"))
  end
end
