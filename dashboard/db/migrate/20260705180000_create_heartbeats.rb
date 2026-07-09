class CreateHeartbeats < ActiveRecord::Migration[8.1]
  # A liveness tick from the listener: it captured and analysed a chunk at this moment,
  # even a quiet one. This is what lets a true 0 (mic up, nothing calling) be told apart
  # from missing data (mic down) — a quiet spell leaves ticks, a stalled feed leaves a
  # gap. Written by the Python listener, so kept to plain columns (no Rails timestamps
  # for it to fill). Core to both runtimes, so NOT guarded to one adapter.
  def change
    return if table_exists?(:heartbeats)

    create_table :heartbeats do |t|
      t.datetime :at, null: false
      t.string :source
    end
    add_index :heartbeats, :at
  end
end
