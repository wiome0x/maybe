class AddRuleTypeToMarketAlertRules < ActiveRecord::Migration[7.2]
  def change
    add_column :market_alert_rules, :rule_type, :string, default: "market", null: false
    add_index :market_alert_rules, [ :user_id, :rule_type ]
  end
end
