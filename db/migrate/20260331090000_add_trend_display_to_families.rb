class AddTrendDisplayToFamilies < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :trend_color_preference, :string, default: "green_up", null: false
  end
end
