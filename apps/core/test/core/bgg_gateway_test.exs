defmodule Core.BggGatewayTest do
  use ExUnit.Case

  import Mox

  alias Core.BggGateway

  setup :verify_on_exit!

  describe "collection/2" do
    test "returns successful response with valid XML data for existing user" do
      expect(Core.MockReqClient, :get, fn url, params, _headers ->
        assert url == "https://boardgamegeek.com/xmlapi2/collection"
        assert params["username"] == "wumbabum"
        {:ok,
         %Req.Response{
           status: 200,
           body: """
            <?xml version="1.0" encoding="utf-8" standalone="yes"?>
              <items totalitems="3" termsofuse="https://boardgamegeek.com/xmlapi/termsofuse" pubdate="Sat, 11 Oct 2025 04:11:33 +0000">
                <item objecttype="thing" objectid="68448" subtype="boardgame" collid="113318978">
                  <name sortindex="1">7 Wonders</name>
                  <yearpublished>2010</yearpublished>
                  <numplays>0</numplays>
                </item>
                <item objecttype="thing" objectid="124742" subtype="boardgame" collid="113319037">
                  <name sortindex="1">Android: Netrunner</name>
                  <yearpublished>2012</yearpublished>
                  <numplays>0</numplays>
                </item>
                <item objecttype="thing" objectid="359871" subtype="boardgame" collid="121983226">
                  <name sortindex="1">Arcs</name>
                  <yearpublished>2024</yearpublished>
                  <numplays>0</numplays>
                </item>
              </items>
            """
         }}
      end)

      assert {:ok, response} = BggGateway.collection("wumbabum")

      case response.status do
        200 ->
          # Verify successful XML response structure
          assert String.starts_with?(response.body, "<?xml version=\"1.0\" encoding=\"utf-8\"")
          assert String.contains?(response.body, "<items totalitems=")

          assert String.contains?(
                   response.body,
                   "termsofuse=\"https://boardgamegeek.com/xmlapi/termsofuse\""
                 )

          assert String.contains?(response.body, "<item objecttype=\"thing\"")
          assert String.contains?(response.body, "subtype=\"boardgame\"")

        202 ->
          # BGG is processing the request - also valid
          assert String.contains?(response.body, "accepted and will be processed")
      end
    end

    test "returns error XML for non-existent user" do
      non_existent_user = "thisuserdoesnotexistanywhere12345"

      expect(Core.MockReqClient, :get, fn url, params, _headers ->
        assert url == "https://boardgamegeek.com/xmlapi2/collection"
        assert params["username"] == non_existent_user
        {:ok,
         %Req.Response{
           status: 200,
           body: """
<?xml version="1.0" encoding="utf-8" standalone="yes" ?>
<errors>
	<error>
		<message>Invalid username specified</message>
	</error>
</errors>
"""
         }}
      end)

      assert {:ok, response} = BggGateway.collection(non_existent_user)
      # BGG returns 200 even for errors
      assert response.status == 200

      # BGG returns error XML for invalid usernames
      assert String.starts_with?(response.body, "<?xml version=\"1.0\" encoding=\"utf-8\"")
      assert String.contains?(response.body, "<errors>")
      assert String.contains?(response.body, "<message>Invalid username specified</message>")
    end
  end
end
