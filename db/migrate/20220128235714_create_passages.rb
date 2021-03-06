class CreatePassages < ActiveRecord::Migration[6.0]
  def change
    create_table :passages do |t|
      # 外部キー制約をつける場合は、きちんとnull: falseを指定しないと、optional: trueを設定していなくてもnullが入ってしまう（nullバリデーションが効かなくなる）。
      t.references :article, null: false, foreign_key: true
      t.text             :text
      t.integer          :lang_number
      t.float            :start_time
      t.integer          :start_time_minutes
      t.float            :start_time_seconds
      t.float            :end_time
      t.integer          :end_time_minutes
      t.float            :end_time_seconds
      t.timestamps
    end
    add_index :passages, :lang_number
  end
end
