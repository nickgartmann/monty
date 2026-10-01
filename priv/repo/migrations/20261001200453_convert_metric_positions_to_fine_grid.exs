defmodule Monty.Repo.Migrations.ConvertMetricPositionsToFineGrid do
  use Ecto.Migration

  # json_each walks every element without dropping additional metric fields.
  # json_group_array keeps the original array order; empty arrays need no write.
  # Integer division rounds nonnegative legacy row indices to the nearest dot.
  def conversion_sql do
    """
    UPDATE models
    SET metrics = (
      SELECT json_group_array(
        json_set(value, '$.x', json_extract(value, '$.x') * 14,
                        '$.y', (json_extract(value, '$.y') * 224 + 10) / 20)
      )
      FROM json_each(models.metrics)
    ),
    lock_version = lock_version + 1
    WHERE json_array_length(metrics) > 0
    """
  end

  def up, do: execute(conversion_sql())

  # Fine-grid positions cannot be restored exactly to the old 280x224px grid.
  def down do
    raise "Irreversible migration: fine-grid metric coordinates cannot be converted back without data loss"
  end
end
