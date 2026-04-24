class AddImportIdempotencyKeyToEntries < ActiveRecord::Migration[7.2]
  def change
    add_column :entries, :import_idempotency_key, :string

    # Unique per account to prevent duplicate imports of the same row
    add_index :entries, [ :account_id, :import_idempotency_key ],
              unique: true,
              where: "import_idempotency_key IS NOT NULL",
              name: "index_entries_on_account_id_and_idempotency_key"
  end
end
