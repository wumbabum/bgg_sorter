defmodule Core.BggGateway.ReqClientTest do
  use ExUnit.Case

  alias Core.BggGateway.ReqClient

  @test_url "https://httpbin.org"

  test "get/3 makes GET request" do
    assert {:ok, response} = ReqClient.get("#{@test_url}/get", %{}, %{})
    assert response.status == 200
  end

  test "post/4 makes POST request with JSON body" do
    body = %{name: "John"}

    assert {:ok, response} = ReqClient.post("#{@test_url}/post", %{}, %{}, body)
    assert response.status == 200
    assert response.body["json"]["name"] == "John"
  end

  test "patch/4 makes PATCH request with JSON body" do
    body = %{status: "updated"}

    assert {:ok, response} = ReqClient.patch("#{@test_url}/patch", %{}, %{}, body)
    assert response.status == 200
    assert response.body["json"]["status"] == "updated"
  end

  test "options/3 makes OPTIONS request" do
    assert {:ok, response} = ReqClient.options("#{@test_url}/get", %{}, %{})
    assert response.status == 200
  end
end
