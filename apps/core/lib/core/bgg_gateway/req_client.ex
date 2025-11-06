defmodule Core.BggGateway.ReqClient do
  @moduledoc """
  HTTP client for making requests to external APIs using Req.

  Provides a unified interface for making HTTP requests with configurable
  parameters, headers, and request bodies.
  """

  defmodule Behaviour do
    @moduledoc """
    Behaviour for HTTP client implementations used by Core.BggGateway.

    Defines callbacks for making HTTP requests with configurable parameters,
    headers, and request bodies.
    """

    @type headers :: [{String.t(), String.t()}] | map()
    @type params :: [{atom() | String.t(), any()}] | map()
    @type body :: binary() | map() | list()
    @type response :: {:ok, Req.Response.t()} | {:error, Exception.t()}

    @doc "Makes a GET request to the specified URL."
    @callback get(String.t(), params(), headers()) :: response()

    @doc "Makes a POST request to the specified URL."
    @callback post(String.t(), params(), headers(), body()) :: response()

    @doc "Makes a PATCH request to the specified URL."
    @callback patch(String.t(), params(), headers(), body()) :: response()

    @doc "Makes an OPTIONS request to the specified URL."
    @callback options(String.t(), params(), headers()) :: response()
  end

  require Logger

  @behaviour Behaviour

  @type headers :: [{String.t(), String.t()}] | map()
  @type params :: [{atom() | String.t(), any()}] | map()
  @type body :: binary() | map() | list()
  @type response :: {:ok, Req.Response.t()} | {:error, Exception.t()}

  @doc "Makes a GET request to the specified URL."
  @impl Behaviour
  def get(url, params, headers, opts \\ []) do
    redacted_headers = redact_auth_headers(headers)

    Logger.info(
      "Making GET request with args: #{inspect(%{url: url, params: params, headers: redacted_headers})}"
    )

    case Req.new(req_options(opts)) |> Req.get(url: url, params: params, headers: headers) do
      {:ok, _response} = result ->
        result

      {:error, reason} = error ->
        Logger.error("BGG HTTP: Request failed: #{inspect(reason)}")
        error
    end
  end

  @doc "Makes a POST request to the specified URL."
  @impl Behaviour
  def post(url, params, headers, body \\ nil, opts \\ []) do
    request_opts =
      case body do
        nil -> [params: params, headers: headers]
        body when is_map(body) -> [params: params, headers: headers, json: body]
        body -> [params: params, headers: headers, body: body]
      end

    Req.new(req_options(opts)) |> Req.post([url: url] ++ request_opts)
  end

  @doc "Makes a PATCH request to the specified URL."
  @impl Behaviour
  def patch(url, params, headers, body \\ nil, opts \\ []) do
    request_opts =
      case body do
        nil -> [params: params, headers: headers]
        body when is_map(body) -> [params: params, headers: headers, json: body]
        body -> [params: params, headers: headers, body: body]
      end

    Req.new(req_options(opts)) |> Req.patch([url: url] ++ request_opts)
  end

  @doc "Makes an OPTIONS request to the specified URL."
  @impl Behaviour
  def options(url, params, headers, opts \\ []) do
    Req.new(req_options(opts))
    |> Req.request(method: :options, url: url, params: params, headers: headers)
  end

  # Private helper to get configured request options
  defp req_options(opts) do
    # BGG API requires retry logic due to rate limiting and service issues
    max_retries = Keyword.get(opts, :max_retries, 3)
    plug = Keyword.get(opts, :plug)

    base_opts = [
      retry: &should_retry?/2,
      max_retries: max_retries,
      receive_timeout: 30_000
    ]

    if plug, do: Keyword.put(base_opts, :plug, plug), else: base_opts
  end

  # Custom retry logic for BGG API quirks
  defp should_retry?(_req, %Req.Response{status: 202}), do: {:delay, 3500}
  defp should_retry?(_req, %Req.Response{status: 429}), do: {:delay, 5000}
  defp should_retry?(_req, %Req.Response{status: status}) when status >= 500, do: {:delay, 3500}
  defp should_retry?(_req, %Req.TransportError{}), do: {:delay, 3500}
  defp should_retry?(_req, _result), do: false

  # Redacts sensitive headers for logging
  defp redact_auth_headers(headers) when is_map(headers) do
    Map.update(headers, "Authorization", nil, fn _ -> "[REDACTED]" end)
  end

  defp redact_auth_headers(headers) when is_list(headers) do
    Enum.map(headers, fn
      {"Authorization", _} -> {"Authorization", "[REDACTED]"}
      other -> other
    end)
  end

  defp redact_auth_headers(headers), do: headers
end
