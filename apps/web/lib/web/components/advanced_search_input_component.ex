defmodule Web.Components.AdvancedSearchInputComponent do
  @moduledoc "Individual input component for advanced search fields."

  use Phoenix.Component

  # Text input field
  def text_input(assigns) do
    # Add immediate filtering unless it's the username field
    assigns = assign(assigns, :immediate_filtering, assigns[:name] != "username")

    ~H"""
    <tr>
      <td width="25%" align="right"><b>{@label}</b></td>
      <td width="75%">
        <input
          id={@id}
          type="text"
          name={@name}
          size={@size || "35"}
          value={@value || ""}
          placeholder={@placeholder || ""}
          autocomplete={assigns[:autocomplete] || "off"}
          {if @immediate_filtering do
            [
              "phx-keyup": "immediate_filter",
              "phx-debounce": "500",
              "phx-value-field": @name
            ]
          else
            []
          end}
        />
      </td>
    </tr>
    """
  end

  # Number range input (min/max)
  def range_input(assigns) do
    ~H"""
    <tr>
      <td width="25%" align="right"><b>{@label}</b></td>
      <td width="75%">
        <input
          id={"#{@id}-min"}
          type="text"
          name={"#{@name}[min]"}
          size="5"
          value={@min_value || ""}
          placeholder="Min"
          phx-keyup="immediate_filter"
          phx-debounce="500"
          phx-value-field={"#{@name}_min"}
        />
        <span aria-hidden="true"> to </span>
        <input
          id={"#{@id}-max"}
          type="text"
          name={"#{@name}[max]"}
          size="5"
          value={@max_value || ""}
          placeholder="Max"
          phx-keyup="immediate_filter"
          phx-debounce="500"
          phx-value-field={"#{@name}_max"}
        />
        <%= if assigns[:suffix] do %>
          <span aria-hidden="true">{@suffix}</span>
        <% end %>
      </td>
    </tr>
    """
  end

  # Single number input
  def number_input(assigns) do
    ~H"""
    <tr>
      <td width="25%" align="right"><b>{@label}</b></td>
      <td width="75%">
        <input
          id={@id}
          type="text"
          name={@name}
          size="5"
          value={@value || ""}
          placeholder={@placeholder || ""}
          phx-keyup="immediate_filter"
          phx-debounce="500"
          phx-value-field={@name}
        />
        <%= if assigns[:suffix] do %>
          <span aria-hidden="true">{@suffix}</span>
        <% end %>
      </td>
    </tr>
    """
  end

  # Player count dropdown
  def player_select(assigns) do
    ~H"""
    <tr>
      <td width="25%" align="right"><b>Number of Players</b></td>
      <td width="75%">
        <select
          id="players-select"
          name="players"
          size="1"
          phx-change="immediate_filter"
          phx-value-field="players"
        >
          <option value="">Any</option>
          <option value="1" selected={@selected_players == "1"}>1</option>
          <option value="2" selected={@selected_players == "2"}>2</option>
          <option value="3" selected={@selected_players == "3"}>3</option>
          <option value="4" selected={@selected_players == "4"}>4</option>
          <option value="5" selected={@selected_players == "5"}>5</option>
          <option value="6" selected={@selected_players == "6"}>6</option>
          <option value="7" selected={@selected_players == "7"}>7</option>
          <option value="8" selected={@selected_players == "8"}>8</option>
          <option value="9" selected={@selected_players == "9"}>9</option>
          <option value="10+" selected={@selected_players == "10+"}>10+</option>
        </select>
        <div class="help-text">
          Will match games that support this number of players
        </div>
      </td>
    </tr>
    """
  end

  # Playing time dropdown
  def playtime_select(assigns) do
    ~H"""
    <tr>
      <td width="25%" align="right"><b>{@label}</b></td>
      <td width="75%">
        <select id={@id} name={@name} size="1">
          <option value="">Any</option>
          <option value="15" selected={@selected_time == "15"}>15 minutes</option>
          <option value="30" selected={@selected_time == "30"}>30 minutes</option>
          <option value="45" selected={@selected_time == "45"}>45 minutes</option>
          <option value="60" selected={@selected_time == "60"}>60 minutes</option>
          <option value="90" selected={@selected_time == "90"}>90 minutes</option>
          <option value="120" selected={@selected_time == "120"}>2 hours</option>
          <option value="150" selected={@selected_time == "150"}>2.5 hours</option>
          <option value="180" selected={@selected_time == "180"}>3 hours</option>
          <option value="240" selected={@selected_time == "240"}>4 hours</option>
          <option value="300" selected={@selected_time == "300"}>5+ hours</option>
        </select>
        <%= if assigns[:suffix] do %>
          <span aria-hidden="true"> ({@suffix})</span>
        <% end %>
      </td>
    </tr>
    """
  end
end
