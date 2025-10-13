defmodule Core.BggGatewayTest do
  use ExUnit.Case
  @moduletag :capture_log

  import Mox

  alias Core.BggGateway
  alias Core.Schemas.{CollectionResponse, Thing}

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

      assert {:ok, collection} = BggGateway.collection("wumbabum")

      # Verify parsed collection structure
      assert %CollectionResponse{} = collection
      assert collection.totalitems == "3"
      assert length(collection.items) == 3

      # Verify first item
      first_item = Enum.at(collection.items, 0)
      assert %Thing{} = first_item
      assert first_item.id == "68448"
      assert first_item.type == "thing"
      assert first_item.subtype == "boardgame"
      assert first_item.primary_name == "7 Wonders"
      assert first_item.yearpublished == "2010"

      # Verify second item
      second_item = Enum.at(collection.items, 1)
      assert second_item.primary_name == "Android: Netrunner"
      assert second_item.yearpublished == "2012"

      # Verify third item
      third_item = Enum.at(collection.items, 2)
      assert third_item.primary_name == "Arcs"
      assert third_item.yearpublished == "2024"
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

      assert {:error, reason} = BggGateway.collection(non_existent_user)
      # BGG returns error XML with specific error message
      assert reason == "BGG API error: Invalid username specified"
    end

    test "returns :not_found for non-200 HTTP status" do
      expect(Core.MockReqClient, :get, fn _url, _params, _headers ->
        {:ok, %Req.Response{status: 404, body: "Not Found"}}
      end)

      assert {:error, :not_found} = BggGateway.collection("testuser")
    end

    test "returns HTTP request error when request fails" do
      expect(Core.MockReqClient, :get, fn _url, _params, _headers ->
        {:error, %RuntimeError{message: "Connection timeout"}}
      end)

      assert {:error, %RuntimeError{message: "Connection timeout"}} =
               BggGateway.collection("testuser")
    end

    test "returns :failed_to_parse_xml for malformed XML" do
      expect(Core.MockReqClient, :get, fn _url, _params, _headers ->
        {:ok, %Req.Response{status: 200, body: "not xml at all"}}
      end)

      assert {:error, :failed_to_parse_xml} = BggGateway.collection("testuser")
    end

    test "returns :invalid_collection_data when changeset validation fails" do
      # Mock valid XML structure but with invalid data that would fail changeset validation
      expect(Core.MockReqClient, :get, fn _url, _params, _headers ->
        {:ok,
         %Req.Response{
           status: 200,
           body: """
           <?xml version="1.0" encoding="utf-8" standalone="yes"?>
           <items totalitems="1" termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
             <item subtype="boardgame">
               <name sortindex="1">Test Game</name>
               <yearpublished value="2024" />
             </item>
           </items>
           """
         }}
      end)

      # This should fail because objectid, objecttype are required but missing
      assert {:error, :invalid_collection_data} = BggGateway.collection("testuser")
    end

    test "accepts valid collection request parameters" do
      expect(Core.MockReqClient, :get, fn url, params, _headers ->
        assert url == "https://boardgamegeek.com/xmlapi2/collection"
        assert params["username"] == "testuser"
        assert params["own"] == "1"
        assert params["stats"] == "1"

        {:ok,
         %Req.Response{
           status: 200,
           body: """
           <?xml version="1.0" encoding="utf-8" standalone="yes"?>
           <items totalitems="0" termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
           </items>
           """
         }}
      end)

      assert {:ok, _collection} =
               BggGateway.collection("testuser", own: 1, stats: 1)
    end

    test "filters out nil values from request parameters" do
      expect(Core.MockReqClient, :get, fn url, params, _headers ->
        assert url == "https://boardgamegeek.com/xmlapi2/collection"
        assert params["username"] == "testuser"
        assert params["own"] == "1"
        # nil values should be filtered out
        refute Map.has_key?(params, "stats")
        refute Map.has_key?(params, "subtype")

        {:ok,
         %Req.Response{
           status: 200,
           body: """
           <?xml version="1.0" encoding="utf-8" standalone="yes"?>
           <items totalitems="0" termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
           </items>
           """
         }}
      end)

      assert {:ok, _collection} =
               BggGateway.collection("testuser", own: 1, stats: nil, subtype: nil)
    end

    test "returns error for invalid collection request parameters" do
      # Invalid minbggrating value (must be 1-10)
      assert {:error, {:invalid_collection_request, errors}} =
               BggGateway.collection("testuser", minbggrating: 15)

      assert Keyword.has_key?(errors, :minbggrating)

      # Invalid wishlistpriority (must be 1-5)
      assert {:error, {:invalid_collection_request, errors}} =
               BggGateway.collection("testuser", wishlistpriority: 10)

      assert Keyword.has_key?(errors, :wishlistpriority)

      # Invalid date format
      assert {:error, {:invalid_collection_request, errors}} =
               BggGateway.collection("testuser", modifiedsince: "invalid-date")

      assert Keyword.has_key?(errors, :modifiedsince)
    end

    test "accepts valid date format for modifiedsince parameter" do
      expect(Core.MockReqClient, :get, fn url, params, _headers ->
        assert url == "https://boardgamegeek.com/xmlapi2/collection"
        assert params["username"] == "testuser"
        assert params["modifiedsince"] == "2025-01-01"

        {:ok,
         %Req.Response{
           status: 200,
           body: """
           <?xml version="1.0" encoding="utf-8" standalone="yes"?>
           <items totalitems="0" termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
           </items>
           """
         }}
      end)

      assert {:ok, _collection} = BggGateway.collection("testuser", modifiedsince: "2025-01-01")
    end
  end

  describe "things/2" do
    test "returns successful response with valid XML data for existing things" do
      expect(Core.MockReqClient, :get, fn url, params, _headers ->
        assert url == "https://boardgamegeek.com/xmlapi2/thing"
        assert params["id"] == "68448,124742,359871"
        assert params["stats"] == "1"

        {:ok,
         %Req.Response{
           status: 200,
           body: """
           <?xml version="1.0" encoding="utf-8" standalone="yes"?>
           <items termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
             <item type="boardgame" id="68448">
               <thumbnail>https://cf.geekdo-images.com/7k_nOxpO9OGIjhLq2BUZdA__thumb/img/w_coXfYWpbPKdWTKYi8QGqV5_DUl8=/fit-in/200x150/filters:strip_icc()/pic860217.jpg</thumbnail>
               <image>https://cf.geekdo-images.com/7k_nOxpO9OGIjhLq2BUZdA__original/img/S4qqmhWtqaIvMST2HvNj7YsYaQI=/0x0/filters:format(jpeg)/pic860217.jpg</image>
               <name type="primary" sortindex="1" value="7 Wonders" />
               <description>You are the leader of one of the 7 great cities of the Ancient World.</description>
               <yearpublished value="2010" />
               <minplayers value="2" />
               <maxplayers value="7" />
               <playingtime value="30" />
               <minplaytime value="30" />
               <maxplaytime value="30" />
               <minage value="10" />
               <statistics page="1">
                 <ratings >
                   <usersrated value="96841" />
                   <average value="7.77" />
                   <bayesaverage value="7.52" />
                   <ranks>
                     <rank type="subtype" id="1" name="boardgame" friendlyname="Board Game Rank" value="34" bayesaverage="7.52" />
                   </ranks>
                   <owned value="135268" />
                   <averageweight value="2.33" />
                 </ratings>
               </statistics>
             </item>
             <item type="boardgame" id="124742">
               <thumbnail>https://cf.geekdo-images.com/CqBmSbrGUCLc-5qGS9vA_w__thumb/img/iqWjrKsRoSsagXl8cJdPqQA71Nw=/fit-in/200x150/filters:strip_icc()/pic1324609.jpg</thumbnail>
               <image>https://cf.geekdo-images.com/CqBmSbrGUCLc-5qGS9vA_w__original/img/TjUgZfRQKo_Lz2B9wksINu5Q8Ns=/0x0/filters:format(jpeg)/pic1324609.jpg</image>
               <name type="primary" sortindex="1" value="Android: Netrunner" />
               <description>Welcome to New Angeles. The android and human worlds have merged.</description>
               <yearpublished value="2012" />
               <minplayers value="2" />
               <maxplayers value="2" />
               <playingtime value="45" />
               <minplaytime value="45" />
               <maxplaytime value="45" />
               <minage value="14" />
               <statistics page="1">
                 <ratings >
                   <usersrated value="44371" />
                   <average value="8.25" />
                   <bayesaverage value="7.75" />
                   <ranks>
                     <rank type="subtype" id="1" name="boardgame" friendlyname="Board Game Rank" value="20" bayesaverage="7.75" />
                   </ranks>
                   <owned value="61394" />
                   <averageweight value="3.21" />
                 </ratings>
               </statistics>
             </item>
             <item type="boardgame" id="359871">
               <thumbnail>https://cf.geekdo-images.com/RjgjD6WW1tN4pBP8C0Pxng__thumb/img/XHIO7Lnn-EjwwYhvzJrGpQ8W6Ho=/fit-in/200x150/filters:strip_icc()/pic7605536.jpg</thumbnail>
               <image>https://cf.geekdo-images.com/RjgjD6WW1tN4pBP8C0Pxng__original/img/nnz7TkFXjXGdMTl__A3LtLYy4vM=/0x0/filters:format(jpeg)/pic7605536.jpg</image>
               <name type="primary" sortindex="1" value="Arcs" />
               <description>Arcs is a sharp sci-fi strategy game for 2–4 players, set in a dark future.</description>
               <yearpublished value="2024" />
               <minplayers value="1" />
               <maxplayers value="4" />
               <playingtime value="90" />
               <minplaytime value="60" />
               <maxplaytime value="90" />
               <minage value="14" />
               <statistics page="1">
                 <ratings >
                   <usersrated value="4251" />
                   <average value="8.66" />
                   <bayesaverage value="7.05" />
                   <ranks>
                     <rank type="subtype" id="1" name="boardgame" friendlyname="Board Game Rank" value="153" bayesaverage="7.05" />
                   </ranks>
                   <owned value="10891" />
                   <averageweight value="3.82" />
                 </ratings>
               </statistics>
             </item>
           </items>
           """
         }}
      end)

      assert {:ok, things} = BggGateway.things(["68448", "124742", "359871"])

      # Verify we get a list of Things
      assert is_list(things)
      assert length(things) == 3

      # Verify first thing
      first_thing = Enum.at(things, 0)
      assert %Thing{} = first_thing
      assert first_thing.id == "68448"
      assert first_thing.type == "boardgame"
      assert first_thing.primary_name == "7 Wonders"
      assert first_thing.yearpublished == "2010"

      assert first_thing.description ==
               "You are the leader of one of the 7 great cities of the Ancient World."

      assert first_thing.thumbnail =~ "pic860217.jpg"
      assert first_thing.image =~ "pic860217.jpg"
      assert first_thing.minplayers == "2"
      assert first_thing.maxplayers == "7"
      assert first_thing.playingtime == "30"
      assert first_thing.minage == "10"
      assert first_thing.average == "7.77"
      assert first_thing.bayesaverage == "7.52"
      assert first_thing.rank == "34"
      assert first_thing.owned == "135268"
      assert first_thing.averageweight == "2.33"
      assert first_thing.usersrated == "96841"

      # Verify second thing
      second_thing = Enum.at(things, 1)
      assert second_thing.id == "124742"
      assert second_thing.primary_name == "Android: Netrunner"
      assert second_thing.yearpublished == "2012"
      assert second_thing.average == "8.25"
      assert second_thing.rank == "20"

      # Verify third thing
      third_thing = Enum.at(things, 2)
      assert third_thing.id == "359871"
      assert third_thing.primary_name == "Arcs"
      assert third_thing.yearpublished == "2024"
      assert third_thing.average == "8.66"
      assert third_thing.rank == "153"
    end

    test "returns error XML for invalid thing IDs" do
      expect(Core.MockReqClient, :get, fn url, params, _headers ->
        assert url == "https://boardgamegeek.com/xmlapi2/thing"
        assert params["id"] == "999999999"
        assert params["stats"] == "1"

        {:ok,
         %Req.Response{
           status: 200,
           body: """
           <?xml version="1.0" encoding="utf-8" standalone="yes" ?>
           <errors>
           	<error>
           		<message>Item not found</message>
           	</error>
           </errors>
           """
         }}
      end)

      assert {:error, reason} = BggGateway.things(["999999999"])
      # BGG returns error XML with specific error message
      assert reason == "BGG API error: Item not found"
    end

    test "returns :not_found for non-200 HTTP status" do
      expect(Core.MockReqClient, :get, fn _url, _params, _headers ->
        {:ok, %Req.Response{status: 404, body: "Not Found"}}
      end)

      assert {:error, :not_found} = BggGateway.things(["68448"])
    end

    test "returns HTTP request error when request fails" do
      expect(Core.MockReqClient, :get, fn _url, _params, _headers ->
        {:error, %RuntimeError{message: "Connection timeout"}}
      end)

      assert {:error, %RuntimeError{message: "Connection timeout"}} = BggGateway.things(["68448"])
    end

    test "returns :failed_to_parse_xml for malformed XML" do
      expect(Core.MockReqClient, :get, fn _url, _params, _headers ->
        {:ok, %Req.Response{status: 200, body: "not xml at all"}}
      end)

      assert {:error, :failed_to_parse_xml} = BggGateway.things(["68448"])
    end

    test "returns :invalid_thing_data when changeset validation fails" do
      # Mock valid XML structure but with invalid data that would fail changeset validation
      expect(Core.MockReqClient, :get, fn _url, _params, _headers ->
        {:ok,
         %Req.Response{
           status: 200,
           body: """
           <?xml version="1.0" encoding="utf-8" standalone="yes"?>
           <items termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
             <item>
               <name type="primary" value="Test Game" />
               <yearpublished value="2024" />
             </item>
           </items>
           """
         }}
      end)

      # This should fail because id and type are required but missing
      assert {:error, :invalid_thing_data} = BggGateway.things(["68448"])
    end

    test "handles integer IDs" do
      expect(Core.MockReqClient, :get, fn url, params, _headers ->
        assert url == "https://boardgamegeek.com/xmlapi2/thing"
        assert params["id"] == "68448"
        assert params["stats"] == "1"

        {:ok,
         %Req.Response{
           status: 200,
           body: """
           <?xml version="1.0" encoding="utf-8" standalone="yes"?>
           <items termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
             <item type="boardgame" id="68448">
               <name type="primary" value="7 Wonders" />
               <yearpublished value="2010" />
             </item>
           </items>
           """
         }}
      end)

      assert {:ok, [thing]} = BggGateway.things([68448])
      assert thing.id == "68448"
      assert thing.type == "boardgame"
      assert thing.primary_name == "7 Wonders"
    end

    test "handles mixed string and integer IDs" do
      expect(Core.MockReqClient, :get, fn url, params, _headers ->
        assert url == "https://boardgamegeek.com/xmlapi2/thing"
        assert params["id"] == "68448,124742"

        {:ok,
         %Req.Response{
           status: 200,
           body: """
           <?xml version="1.0" encoding="utf-8" standalone="yes"?>
           <items termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
             <item type="boardgame" id="68448">
               <name type="primary" value="7 Wonders" />
               <yearpublished value="2010" />
             </item>
             <item type="boardgame" id="124742">
               <name type="primary" value="Android: Netrunner" />
               <yearpublished value="2012" />
             </item>
           </items>
           """
         }}
      end)

      assert {:ok, things} = BggGateway.things([68448, "124742"])
      assert length(things) == 2
      assert Enum.at(things, 0).id == "68448"
      assert Enum.at(things, 1).id == "124742"
    end
  end
end
