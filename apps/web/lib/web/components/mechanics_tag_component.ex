defmodule Web.Components.MechanicsTagComponent do
  @moduledoc "Reusable mechanics tag component with highlighting and click support."

  use Phoenix.Component

  @doc """
  Renders a mechanics tag with optional highlighting and click behavior.
  
  ## Examples
  
      <MechanicsTagComponent.mechanic_tag mechanic={mechanic} highlighted={true} clickable={true} />
      <MechanicsTagComponent.mechanic_tag mechanic={mechanic} size={:small} />
  """
  attr :mechanic, :map, required: true, doc: "The mechanic struct with name field"
  attr :highlighted, :boolean, default: false, doc: "Whether the tag should be highlighted"
  attr :size, :atom, default: :normal, values: [:normal, :small], doc: "Size variant of the tag"
  attr :clickable, :boolean, default: false, doc: "Whether the tag should be clickable"

  def mechanic_tag(assigns) do
    ~H"""
    <span
      class={build_tag_classes(assigns)}
      phx-click={@clickable && "toggle_mechanic"}
      phx-value-mechanic_id={@clickable && @mechanic.id}
      tabindex={@clickable && "0"}
    >
      {@mechanic.name}
    </span>
    """
  end

  defp build_tag_classes(assigns) do
    base_class = "mechanic-tag"
    
    classes = [
      base_class,
      assigns.highlighted && "#{base_class}--highlighted",
      assigns.size == :small && "#{base_class}--small",
      assigns.clickable && "#{base_class}--clickable"
    ]
    
    classes
    |> Enum.filter(&(&1))
    |> Enum.join(" ")
  end
end