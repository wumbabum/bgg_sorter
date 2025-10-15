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
  def get(url, params, headers) do
    start_time = System.monotonic_time(:millisecond)
    
    Logger.info(
      "🌍 BGG HTTP: Making GET request to #{url} with params: #{inspect(params)}"
    )

    opts = [params: params, headers: headers] ++ req_options()
    
    case Req.get(url, opts) do
      {:ok, response} = result ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.info("🌍 BGG HTTP: Request completed in #{duration}ms (status: #{response.status})")
        result
        
      {:error, reason} = error ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.error("🌍 BGG HTTP: Request failed after #{duration}ms: #{inspect(reason)}")
        error
    end
  end

  @doc "Makes a POST request to the specified URL."
  @impl Behaviour
  def post(url, params, headers, body \\ nil) do
    request_opts = [params: params, headers: headers] ++ req_options()

    request_opts =
      case body do
        nil -> request_opts
        body when is_map(body) -> Keyword.put(request_opts, :json, body)
        body -> Keyword.put(request_opts, :body, body)
      end

    Req.post(url, request_opts)
  end

  @doc "Makes a PATCH request to the specified URL."
  @impl Behaviour
  def patch(url, params, headers, body \\ nil) do
    request_opts = [params: params, headers: headers] ++ req_options()

    request_opts =
      case body do
        nil -> request_opts
        body when is_map(body) -> Keyword.put(request_opts, :json, body)
        body -> Keyword.put(request_opts, :body, body)
      end

    Req.patch(url, request_opts)
  end

  @doc "Makes an OPTIONS request to the specified URL."
  @impl Behaviour
  def options(url, params, headers) do
    opts = [method: :options, url: url, params: params, headers: headers] ++ req_options()
    Req.request(opts)
  end

  # Private helper to get configured request options
  defp req_options do
    # BGG API requires retry logic due to rate limiting and service issues
    [
      retry: :transient,
      retry_delay: fn attempt -> 
        delay = min(1000 * :math.pow(2, attempt - 1), 10_000)
        Logger.info("🔄 BGG RETRY: Attempt #{attempt}, waiting #{trunc(delay)}ms before retry")
        trunc(delay)
      end,
      max_retries: 3,
      receive_timeout: 30_000
    ]
  end
end
