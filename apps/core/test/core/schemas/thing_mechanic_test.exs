defmodule Core.Schemas.ThingMechanicTest do
  use Core.DataCase, async: true

  alias Core.Schemas.{ThingMechanic, Thing, Mechanic}

  setup do
    # Create a test thing
    {:ok, thing} =
      %Thing{}
      |> Thing.changeset(%{
        id: "12345",
        type: "boardgame",
        primary_name: "Test Game",
        schema_version: 2
      })
      |> Repo.insert()

    # Create a test mechanic
    {:ok, mechanic} =
      %Mechanic{}
      |> Mechanic.changeset(%{
        name: "Hand Management",
        slug: "hand-management"
      })
      |> Repo.insert()

    %{thing: thing, mechanic: mechanic}
  end

  describe "changeset/2" do
    test "creates valid changeset with thing_id and mechanic_id", %{
      thing: thing,
      mechanic: mechanic
    } do
      params = %{
        thing_id: thing.id,
        mechanic_id: mechanic.id
      }

      changeset = ThingMechanic.changeset(%ThingMechanic{}, params)

      assert changeset.valid?
      assert get_change(changeset, :thing_id) == thing.id
      assert get_change(changeset, :mechanic_id) == mechanic.id
    end

    test "requires thing_id field", %{mechanic: mechanic} do
      params = %{mechanic_id: mechanic.id}

      changeset = ThingMechanic.changeset(%ThingMechanic{}, params)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).thing_id
    end

    test "requires mechanic_id field", %{thing: thing} do
      params = %{thing_id: thing.id}

      changeset = ThingMechanic.changeset(%ThingMechanic{}, params)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).mechanic_id
    end

    test "validates unique constraint on thing_id and mechanic_id", %{
      thing: thing,
      mechanic: mechanic
    } do
      # First ThingMechanic
      {:ok, _first} =
        %ThingMechanic{}
        |> ThingMechanic.changeset(%{thing_id: thing.id, mechanic_id: mechanic.id})
        |> Repo.insert()

      # Second ThingMechanic with same combination
      changeset =
        ThingMechanic.changeset(%ThingMechanic{}, %{thing_id: thing.id, mechanic_id: mechanic.id})

      assert {:error, failed_changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(failed_changeset).thing_id
    end
  end

  describe "for_thing/2" do
    test "returns query for finding ThingMechanics by thing_id", %{
      thing: thing,
      mechanic: mechanic
    } do
      # Create ThingMechanic
      {:ok, thing_mechanic} =
        %ThingMechanic{}
        |> ThingMechanic.changeset(%{thing_id: thing.id, mechanic_id: mechanic.id})
        |> Repo.insert()

      # Query using for_thing
      results =
        ThingMechanic
        |> ThingMechanic.for_thing(thing.id)
        |> Repo.all()

      assert length(results) == 1
      assert hd(results).id == thing_mechanic.id
      assert hd(results).thing_id == thing.id
      assert hd(results).mechanic_id == mechanic.id
    end

    test "returns empty list when no ThingMechanics exist for thing_id", %{thing: thing} do
      results =
        ThingMechanic
        |> ThingMechanic.for_thing(thing.id)
        |> Repo.all()

      assert results == []
    end

    test "only returns ThingMechanics for specified thing_id", %{mechanic: mechanic} do
      # Create two different things
      {:ok, thing1} =
        %Thing{}
        |> Thing.changeset(%{
          id: "thing1",
          type: "boardgame",
          primary_name: "Game 1",
          schema_version: 2
        })
        |> Repo.insert()

      {:ok, thing2} =
        %Thing{}
        |> Thing.changeset(%{
          id: "thing2",
          type: "boardgame",
          primary_name: "Game 2",
          schema_version: 2
        })
        |> Repo.insert()

      # Create ThingMechanics for both
      {:ok, tm1} =
        %ThingMechanic{}
        |> ThingMechanic.changeset(%{thing_id: thing1.id, mechanic_id: mechanic.id})
        |> Repo.insert()

      {:ok, _tm2} =
        %ThingMechanic{}
        |> ThingMechanic.changeset(%{thing_id: thing2.id, mechanic_id: mechanic.id})
        |> Repo.insert()

      # Query for thing1 only
      results =
        ThingMechanic
        |> ThingMechanic.for_thing(thing1.id)
        |> Repo.all()

      assert length(results) == 1
      assert hd(results).id == tm1.id
      assert hd(results).thing_id == thing1.id
    end
  end

  describe "foreign key constraints" do
    test "prevents insertion with non-existent thing_id", %{mechanic: mechanic} do
      changeset =
        ThingMechanic.changeset(%ThingMechanic{}, %{
          thing_id: "non-existent",
          mechanic_id: mechanic.id
        })

      assert {:error, failed_changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(failed_changeset).thing_id
    end

    test "prevents insertion with non-existent mechanic_id", %{thing: thing} do
      fake_uuid = Ecto.UUID.generate()

      changeset =
        ThingMechanic.changeset(%ThingMechanic{}, %{
          thing_id: thing.id,
          mechanic_id: fake_uuid
        })

      assert {:error, failed_changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(failed_changeset).mechanic_id
    end
  end
end
