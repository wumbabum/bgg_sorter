defmodule Core.BggGateway do
  @moduledoc """
  Gateway module for interacting with BoardGameGeek API.
  """

  @base_url "https://boardgamegeek.com/xmlapi2"

  @doc "Retrieves a user's board game collection from BoardGameGeek."
  @spec collection(String.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def collection(username, opts \\ []) do
    params =
      opts
      |> Keyword.put(:username, to_string(username))
      |> Enum.into(%{})
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
      |> Enum.into(%{})

    url = "#{@base_url}/collection"
    req_client().get(url, params, %{})
  end

  defp req_client do
    Application.get_env(:core, :bgg_req_client, Core.BggGateway.ReqClient)
  end
end
