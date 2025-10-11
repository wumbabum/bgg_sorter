defmodule Core.BggGateway do
  @moduledoc """
  Gateway module for interacting with BoardGameGeek API.
  """

  import SweetXml
  require Logger

  alias Core.Schemas.{CollectionResponse, CollectionRequest, Thing}

  @base_url "https://boardgamegeek.com/xmlapi2"

  @doc "Retrieves a user's board game collection from BoardGameGeek."
  @spec collection(String.t(), keyword()) :: {:ok, CollectionResponse.t()} | {:error, Exception.t()}
  def collection(username, opts \\ []) do
    request_params =
      opts
      |> Keyword.put(:username, to_string(username))
      |> Enum.into(%{})

    url = "#{@base_url}/collection"

    with {:ok, validated_params} <- cast_collection_request(request_params),
         Logger.info("Fetching collection for #{username} with params: #{inspect(validated_params)}"),
         {:ok, %Req.Response{status: 200} = response} <- req_client().get(url, validated_params, %{}),
         {:ok, collection} <- parse_xml_response(response.body) do
      {:ok, collection}
    else
      {:ok, %Req.Response{status: status} = response} ->
        Logger.error("Unexpected response status: #{status}, body: #{response.body}")
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_xml_response(xml_body) do
    with {:ok, parsed_xml} <- parse_xml(xml_body),
         {:ok, collection_data} <- extract_collection_data(parsed_xml),
         {:ok, collection} <- cast_collection(collection_data) do
      {:ok, collection}
    else
      {:error, reason} -> {:error, reason}
      _error -> {:error, :failed_to_parse_xml_response}
    end
  end

  defp parse_xml(xml_body) do
    # Check if this is an error response by looking for errors element first
    has_errors = xml_body |> xpath(~x"//errors"o)

    if has_errors do
      error_message = xml_body |> xpath(~x"//errors/error/message/text()"s)
      {:error, "BGG API error: #{error_message}"}
    else
      {:ok, xml_body}
    end
  rescue
    _error -> {:error, :failed_to_parse_xml}
  catch
    :exit, _ -> {:error, :failed_to_parse_xml}
  end

  defp extract_collection_data(xml_body) do
    collection_data = xml_body
    |> xmap(
      totalitems: ~x"//items/@totalitems"s,
      termsofuse: ~x"//items/@termsofuse"s,
      items: [
        ~x"//items/item"l,
        id: ~x"./@objectid"s,
        type: ~x"./@objecttype"s,
        subtype: ~x"./@subtype"s,
        primary_name: ~x"./name/text()"s,
        yearpublished: ~x"./yearpublished/text()"so
      ]
    )

    {:ok, collection_data}
  rescue
    _error -> {:error, :failed_to_extract_collection_data}
  catch
    :exit, _ -> {:error, :failed_to_extract_collection_data}
  end

  defp cast_collection(collection_data) do
    case CollectionResponse.changeset(%CollectionResponse{}, collection_data) do
      %Ecto.Changeset{valid?: true} = changeset ->
        {:ok, Ecto.Changeset.apply_changes(changeset)}

      %Ecto.Changeset{valid?: false} ->
        {:error, :invalid_collection_data}
    end
  end

  @doc "Retrieves detailed information for BoardGameGeek things."
  @spec things(list(String.t() | integer()), keyword()) :: {:ok, [Thing.t()]} | {:error, atom()}
  def things(ids, opts \\ []) do
    params =
      opts
      |> Keyword.put(:id, ids |> Enum.map(&to_string/1) |> Enum.join(","))
      |> Keyword.put(:stats, "1")
      |> Enum.into(%{})
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
      |> Enum.into(%{})

    url = "#{@base_url}/thing"

    with {:ok, %Req.Response{status: 200} = response} <- req_client().get(url, params, %{}),
         {:ok, things} <- parse_things_xml_response(response.body) do
      {:ok, things}
    else
      {:ok, %Req.Response{status: status} = response} ->
        Logger.error("Unexpected response status: #{status}, body: #{response.body}")
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_things_xml_response(xml_body) do
    with {:ok, parsed_xml} <- parse_xml(xml_body),
         {:ok, things_data} <- extract_things_data(parsed_xml),
         {:ok, things} <- cast_things(things_data) do
      {:ok, things}
    else
      {:error, reason} -> {:error, reason}
      _error -> {:error, :failed_to_parse_xml_response}
    end
  end

  defp extract_things_data(xml_body) do
    things_data = xml_body
    |> xmap(
      things: [
        ~x"//items/item"l,
        id: ~x"./@id"s,
        type: ~x"./@type"s,
        thumbnail: ~x"./thumbnail/text()"so,
        image: ~x"./image/text()"so,
        primary_name: ~x"./name[@type='primary']/@value"so,
        description: ~x"./description/text()"so,
        yearpublished: ~x"./yearpublished/@value"so,
        minplayers: ~x"./minplayers/@value"so,
        maxplayers: ~x"./maxplayers/@value"so,
        playingtime: ~x"./playingtime/@value"so,
        minplaytime: ~x"./minplaytime/@value"so,
        maxplaytime: ~x"./maxplaytime/@value"so,
        minage: ~x"./minage/@value"so,
        usersrated: ~x".//statistics/ratings/usersrated/@value"so,
        average: ~x".//statistics/ratings/average/@value"so,
        bayesaverage: ~x".//statistics/ratings/bayesaverage/@value"so,
        rank: ~x".//statistics/ratings/ranks/rank[@name='boardgame']/@value"so,
        owned: ~x".//statistics/ratings/owned/@value"so,
        averageweight: ~x".//statistics/ratings/averageweight/@value"so
      ]
    )

    {:ok, things_data.things}
  rescue
    _error -> {:error, :failed_to_extract_things_data}
  catch
    :exit, _ -> {:error, :failed_to_extract_things_data}
  end

  defp cast_things(things_data) do
    things = Enum.map(things_data, fn thing_params ->
      case Thing.changeset(%Thing{}, thing_params) do
        %Ecto.Changeset{valid?: true} = changeset ->
          {:ok, Ecto.Changeset.apply_changes(changeset)}

        %Ecto.Changeset{valid?: false} ->
          {:error, :invalid_thing_data}
      end
    end)

    # Check if all things were successfully cast
    case Enum.find(things, fn {status, _} -> status == :error end) do
      nil -> {:ok, Enum.map(things, fn {:ok, thing} -> thing end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cast_collection_request(params) do
    case CollectionRequest.changeset(%CollectionRequest{}, params) do
      %Ecto.Changeset{valid?: true} = changeset ->
        validated_data = Ecto.Changeset.apply_changes(changeset)
        # Convert to string-keyed map for HTTP request, excluding nil values
        params_map =
          validated_data
          |> Map.from_struct()
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
          |> Enum.into(%{})
        {:ok, params_map}

      %Ecto.Changeset{valid?: false} = changeset ->
        {:error, {:invalid_collection_request, changeset.errors}}
    end
  end

  defp req_client do
    Application.get_env(:core, :bgg_req_client, Core.BggGateway.ReqClient)
  end
end
