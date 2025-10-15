defmodule Core.BggGateway.ReqClientTest do
  use ExUnit.Case, async: true

  alias Core.BggGateway.ReqClient

  test "get/3 makes GET request" do
    Req.Test.stub(Core.BggGateway.ReqClient, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/get"
      Req.Test.json(conn, %{"method" => "GET", "url" => "https://example.com/get"})
    end)

    assert {:ok, response} = ReqClient.get("https://example.com/get", %{}, %{})
    assert response.status == 200
    assert response.body["method"] == "GET"
  end

  test "get/3 passes params and headers correctly" do
    Req.Test.stub(Core.BggGateway.ReqClient, fn conn ->
      assert conn.method == "GET"
      assert conn.params["q"] == "test"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer token"]
      Req.Test.json(conn, %{"received" => "ok"})
    end)

    params = %{"q" => "test"}
    headers = %{"Authorization" => "Bearer token"}
    assert {:ok, response} = ReqClient.get("https://example.com/search", params, headers)
    assert response.status == 200
    assert response.body["received"] == "ok"
  end

  test "post/4 makes POST request with JSON body" do
    body = %{name: "John"}

    Req.Test.stub(Core.BggGateway.ReqClient, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/post"

      # Parse the JSON body
      {:ok, request_body, _conn} = Plug.Conn.read_body(conn)
      parsed_body = Jason.decode!(request_body)
      assert parsed_body["name"] == "John"

      Req.Test.json(conn, %{"json" => parsed_body, "method" => "POST"})
    end)

    assert {:ok, response} = ReqClient.post("https://example.com/post", %{}, %{}, body)
    assert response.status == 200
    assert response.body["json"]["name"] == "John"
    assert response.body["method"] == "POST"
  end

  test "patch/4 makes PATCH request with JSON body" do
    body = %{status: "updated"}

    Req.Test.stub(Core.BggGateway.ReqClient, fn conn ->
      assert conn.method == "PATCH"
      assert conn.request_path == "/patch"

      # Parse the JSON body
      {:ok, request_body, _conn} = Plug.Conn.read_body(conn)
      parsed_body = Jason.decode!(request_body)
      assert parsed_body["status"] == "updated"

      Req.Test.json(conn, %{"json" => parsed_body, "method" => "PATCH"})
    end)

    assert {:ok, response} = ReqClient.patch("https://example.com/patch", %{}, %{}, body)
    assert response.status == 200
    assert response.body["json"]["status"] == "updated"
    assert response.body["method"] == "PATCH"
  end

  test "options/3 makes OPTIONS request" do
    Req.Test.stub(Core.BggGateway.ReqClient, fn conn ->
      assert conn.method == "OPTIONS"
      assert conn.request_path == "/options"

      # OPTIONS requests typically return allowed methods
      conn
      |> Plug.Conn.put_resp_header("allow", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
      |> Plug.Conn.send_resp(200, "")
    end)

    assert {:ok, response} = ReqClient.options("https://example.com/options", %{}, %{})
    assert response.status == 200
    assert response.headers["allow"] == ["GET, POST, PUT, PATCH, DELETE, OPTIONS"]
  end

  test "handles request errors gracefully" do
    Req.Test.stub(Core.BggGateway.ReqClient, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, %Req.TransportError{reason: :timeout}} =
             ReqClient.get("https://example.com/timeout", %{}, %{})
  end
end
