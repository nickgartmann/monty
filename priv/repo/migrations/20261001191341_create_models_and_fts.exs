defmodule Monty.Repo.Migrations.CreateModelsAndFts do
  use Ecto.Migration

  def up do
    create table(:models, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :visibility, :string, null: false, default: "private"
      add :metrics, {:array, :map}, null: false, default: []
      add :lock_version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:models, [:user_id])
    create index(:models, [:visibility, :inserted_at])

    execute """
    CREATE VIRTUAL TABLE model_search USING fts5(
      title, description, content='models', content_rowid='rowid'
    )
    """

    execute """
    CREATE TRIGGER models_search_insert AFTER INSERT ON models BEGIN
      INSERT INTO model_search(rowid, title, description)
      VALUES (new.rowid, new.title, new.description);
    END
    """

    execute """
    CREATE TRIGGER models_search_delete AFTER DELETE ON models BEGIN
      INSERT INTO model_search(model_search, rowid, title, description)
      VALUES ('delete', old.rowid, old.title, old.description);
    END
    """

    execute """
    CREATE TRIGGER models_search_update AFTER UPDATE OF title, description ON models BEGIN
      INSERT INTO model_search(model_search, rowid, title, description)
      VALUES ('delete', old.rowid, old.title, old.description);
      INSERT INTO model_search(rowid, title, description)
      VALUES (new.rowid, new.title, new.description);
    END
    """
  end

  def down do
    execute "DROP TRIGGER models_search_update"
    execute "DROP TRIGGER models_search_delete"
    execute "DROP TRIGGER models_search_insert"
    execute "DROP TABLE model_search"
    drop table(:models)
  end
end
