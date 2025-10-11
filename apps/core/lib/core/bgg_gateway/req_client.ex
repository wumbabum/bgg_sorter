defmodule Core.BggGateway.ReqClient do
  @moduledoc """
  HTTP client for making requests to external APIs using Req.

  Provides a unified interface for making HTTP requests with configurable
  parameters, headers, and request bodies.
  """

  @type headers :: [{String.t(), String.t()}] | map()
  @type params :: [{atom() | String.t(), any()}] | map()
  @type body :: binary() | map() | list()
  @type response :: {:ok, Req.Response.t()} | {:error, Exception.t()}

  @doc """
  Makes a GET request to the specified URL.

  ## Parameters
    - `url` - The URL to request
    - `params` - Query parameters (optional)
    - `headers` - HTTP headers (optional)

  ## Returns
    - `{:ok, %Req.Response{}}` on success
    - `{:error, exception}` on failure

  ## Examples
      iex> Core.BggGateway.ReqClient.get("https://api.example.com/users")
      {:ok, %Req.Response{status: 200, body: ...}}

      iex> Core.BggGateway.ReqClient.get("https://api.example.com/users", %{limit: 10})
      {:ok, %Req.Response{status: 200, body: ...}}
  """
  @spec get(String.t(), params(), headers()) :: response()
  def get(url, params \\ %{}, headers \\ %{}) do
    Req.get(url, params: params, headers: headers)
  end

  @doc """
  Makes a POST request to the specified URL.

  ## Parameters
    - `url` - The URL to request
    - `params` - Query parameters (optional)
    - `headers` - HTTP headers (optional)  
    - `body` - Request body (optional)

  ## Returns
    - `{:ok, %Req.Response{}}` on success
    - `{:error, exception}` on failure

  ## Examples
      iex> Core.BggGateway.ReqClient.post("https://api.example.com/users", %{}, %{}, %{name: "John"})
      {:ok, %Req.Response{status: 201, body: ...}}
  """
  @spec post(String.t(), params(), headers(), body()) :: response()
  def post(url, params \\ %{}, headers \\ %{}, body \\ nil) do
    request_opts = [params: params, headers: headers]
    request_opts = 
      case body do
        nil -> request_opts
        body when is_map(body) -> Keyword.put(request_opts, :json, body)
        body -> Keyword.put(request_opts, :body, body)
      end
    
    Req.post(url, request_opts)
  end

  @doc """
  Makes a PATCH request to the specified URL.

  ## Parameters
    - `url` - The URL to request
    - `params` - Query parameters (optional)
    - `headers` - HTTP headers (optional)
    - `body` - Request body (optional)

  ## Returns
    - `{:ok, %Req.Response{}}` on success
    - `{:error, exception}` on failure

  ## Examples
      iex> Core.BggGateway.ReqClient.patch("https://api.example.com/users/1", %{}, %{}, %{name: "Jane"})
      {:ok, %Req.Response{status: 200, body: ...}}
  """
  @spec patch(String.t(), params(), headers(), body()) :: response()
  def patch(url, params \\ %{}, headers \\ %{}, body \\ nil) do
    request_opts = [params: params, headers: headers]
    request_opts = 
      case body do
        nil -> request_opts
        body when is_map(body) -> Keyword.put(request_opts, :json, body)
        body -> Keyword.put(request_opts, :body, body)
      end
    
    Req.patch(url, request_opts)
  end

  @doc """
  Makes an OPTIONS request to the specified URL.

  ## Parameters
    - `url` - The URL to request
    - `params` - Query parameters (optional)
    - `headers` - HTTP headers (optional)

  ## Returns
    - `{:ok, %Req.Response{}}` on success
    - `{:error, exception}` on failure

  ## Examples
      iex> Core.BggGateway.ReqClient.options("https://api.example.com/users")
      {:ok, %Req.Response{status: 200, headers: ...}}
  """
  @spec options(String.t(), params(), headers()) :: response()
  def options(url, params \\ %{}, headers \\ %{}) do
    Req.request(method: :options, url: url, params: params, headers: headers)
  end
end