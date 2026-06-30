# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_30_130000) do
  create_table "detections", force: :cascade do |t|
    t.string "Com_Name", null: false
    t.float "Confidence"
    t.float "Cutoff"
    t.date "Date"
    t.string "File_Name"
    t.float "Lat"
    t.float "Lon"
    t.float "Overlap"
    t.string "Sci_Name", null: false
    t.float "Sens"
    t.time "Time"
    t.integer "Week"
    t.index ["Date", "Time"], name: "index_detections_on_Date_and_Time"
    t.index ["Sci_Name"], name: "index_detections_on_Sci_Name"
  end

  create_table "species_infos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.text "description_ga"
    t.datetime "fetched_at"
    t.datetime "fetched_ga_at"
    t.string "sci_name", null: false
    t.datetime "updated_at", null: false
    t.index ["sci_name"], name: "index_species_infos_on_sci_name", unique: true
  end
end
