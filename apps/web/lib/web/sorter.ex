defmodule Web.Sorter do
  @moduledoc """
  Handles sorting of Thing collections by a specified field and direction.
  """

  alias Core.Schemas.Thing

  @type sort_direction :: :asc | :desc
  @type sort_field :: :primary_name | :players | :average | :averageweight

  @doc """
  Sorts a list of Things by the specified field and direction.
  
  ## Parameters
  - things: List of Thing structs to sort
  - sort_field: Field to sort by (:primary_name, :players, :average, :averageweight)
  - sort_direction: :asc (default) or :desc
  
  ## Examples
      iex> Web.Sorter.sort_by(things, :primary_name)
      [%Thing{primary_name: "7 Wonders"}, %Thing{primary_name: "Azul"}]
      
      iex> Web.Sorter.sort_by(things, :average, :desc)
      [%Thing{average: "8.5"}, %Thing{average: "7.2"}]
  """
  @spec sort_by([Thing.t()], sort_field(), sort_direction()) :: [Thing.t()]
  def sort_by(things, sort_field, sort_direction \\ :asc) do
    things
    |> Enum.sort_by(&get_sort_value(&1, sort_field), sort_comparator(sort_direction))
  end

  # Extract sortable value from Thing struct
  defp get_sort_value(thing, :primary_name) do
    String.downcase(thing.primary_name || "")
  end
  
  defp get_sort_value(thing, :players) do
    # Sort by minimum players, fallback to 0 for consistent ordering
    case parse_integer(thing.minplayers) do
      int when is_integer(int) -> int
      _ -> 0
    end
  end
  
  defp get_sort_value(thing, :average) do
    # Sort by average rating, fallback to 0.0 for unrated games
    case parse_float(thing.average) do
      float when is_float(float) -> float
      _ -> 0.0
    end
  end
  
  defp get_sort_value(thing, :averageweight) do
    # Sort by complexity weight, fallback to 0.0 for games without weight
    case parse_float(thing.averageweight) do
      float when is_float(float) -> float
      _ -> 0.0
    end
  end

  # Return appropriate sort comparator function
  defp sort_comparator(:asc), do: &<=/2
  defp sort_comparator(:desc), do: &>=/2

  # Helper functions for parsing string values to appropriate types
  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end
  defp parse_integer(_), do: nil

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end
  defp parse_float(_), do: nil
end