defmodule Core.Test.Fixtures.BggResponses do
  @moduledoc """
  BGG API XML response fixtures for testing mechanics functionality.

  These fixtures are based on real BoardGameGeek API responses and include
  comprehensive mechanics data to test the new relational mechanics architecture.
  """

  @doc """
  BGG XML response for Brass: Birmingham with real mechanics data.

  This is based on an actual BGG API response and includes 14 mechanics
  to test bulk mechanics processing and association management.
  """
  def things_with_mechanics_xml do
    File.read!(Path.join([__DIR__, "things_response_success.xml"]))
  end

  @doc """
  BGG XML response for games without mechanics data.

  Used to test games that have no mechanics information
  and ensure the system handles empty/missing mechanics gracefully.
  """
  def things_without_mechanics_xml do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <items termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
      <item type="boardgame" id="123456">
        <thumbnail>https://example.com/thumb.jpg</thumbnail>
        <image>https://example.com/image.jpg</image>
        <name type="primary" sortindex="1" value="Simple Game" />
        <description>A simple game with no mechanics data for testing.</description>
        <yearpublished value="2020" />
        <minplayers value="2" />
        <maxplayers value="4" />
        <playingtime value="30" />
        <minplaytime value="20" />
        <maxplaytime value="30" />
        <minage value="8" />
        <link type="boardgamecategory" id="1030" value="Party Game" />
        <!-- No mechanics links in this response -->
        <statistics>
          <ratings>
            <usersrated value="500" />
            <average value="6.50" />
            <bayesaverage value="5.88" />
            <ranks>
              <rank type="subtype" id="1" name="boardgame" value="5000" />
            </ranks>
            <stddev value="1.45" />
            <median value="0" />
            <owned value="1200" />
            <trading value="50" />
            <wanting value="25" />
            <wishing value="100" />
            <numcomments value="75" />
            <numweights value="30" />
            <averageweight value="1.75" />
          </ratings>
        </statistics>
      </item>
    </items>
    """
  end

  @doc """
  BGG XML response for games with edge case mechanics.

  Tests mechanics with special characters, spaces, and other edge cases
  to ensure robust parsing and slug generation.
  """
  def things_edge_cases_xml do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <items termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
      <item type="boardgame" id="999999">
        <thumbnail>https://example.com/edge.jpg</thumbnail>
        <image>https://example.com/edge.jpg</image>
        <name type="primary" sortindex="1" value="Edge Case Game" />
        <description>A game for testing edge cases in mechanics parsing &amp; handling.</description>
        <yearpublished value="2021" />
        <minplayers value="2" />
        <maxplayers value="2" />
        <playingtime value="45" />
        <minplaytime value="30" />
        <maxplaytime value="45" />
        <minage value="10" />
        <link type="boardgamecategory" id="1009" value="Abstract Strategy" />
        <link type="boardgamemechanic" id="2956" value="Special Characters: &amp; &lt; &gt; &quot;" />
        <link type="boardgamemechanic" id="2999" value="  Spaces   And   Tabs  " />
        <link type="boardgamemechanic" id="3000" value="Very-Long-Hyphenated-Mechanic-Name" />
        <link type="boardgamemechanic" id="3001" value="Apostrophe's &amp; Quotes" />
        <statistics>
          <ratings>
            <usersrated value="100" />
            <average value="5.25" />
            <bayesaverage value="4.85" />
            <ranks>
              <rank type="subtype" id="1" name="boardgame" value="10000" />
            </ranks>
            <stddev value="2.15" />
            <median value="0" />
            <owned value="250" />
            <trading value="15" />
            <wanting value="5" />
            <wishing value="20" />
            <numcomments value="25" />
            <numweights value="10" />
            <averageweight value="2.50" />
          </ratings>
        </statistics>
      </item>
    </items>
    """
  end

  @doc """
  Collection XML response fixture.

  Used for testing collection endpoint responses that don't include
  detailed mechanics but provide the basic game list for caching.
  """
  def collection_xml do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <items totalitems="2" termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
      <item objecttype="thing" objectid="224517" subtype="boardgame">
        <name sortindex="1">Brass: Birmingham</name>
        <yearpublished>2018</yearpublished>
      </item>
      <item objecttype="thing" objectid="123456" subtype="boardgame">
        <name sortindex="1">Simple Game</name>
        <yearpublished>2020</yearpublished>
      </item>
    </items>
    """
  end
end
