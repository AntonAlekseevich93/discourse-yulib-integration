class CreateYulibBooks < ActiveRecord::Migration[7.0]
  def change
    create_table :yulib_books do |t|
      # Системные поля Discourse
      t.integer :user_id, null: false           # Кому принадлежит книга на форуме

      # Поля из твоего Ktor (адаптированные под snake_case)
      t.string  :book_id, null: false           # Твой bookId
      t.string  :author_id
      t.string  :author_name
      t.string  :book_name
      t.string  :user_cover_url
      t.integer :page_count
      t.string  :isbn
      t.string  :reading_status
      t.string  :age_restriction
      t.integer :book_genre_id
      t.string  :image_name
      t.bigint  :start_date                     # Используем bigint для Long (timestamp)
      t.bigint  :end_date
      t.bigint  :timestamp_of_creating
      t.bigint  :timestamp_of_updating
      t.integer :external_user_id               # Твой userId из Ktor
      t.boolean :is_visible_for_all_users, default: true
      t.text    :description                    # Используем text для длинных строк
      t.integer :image_folder_id
      t.string  :main_book_id
      t.string  :publication_year
      t.bigint  :timestamp_of_reading_done

      t.timestamps # Поля created_at и updated_at самого Дискорса
    end

    # Индексы для скорости
    add_index :yulib_books, :user_id
    # Уникальный индекс, чтобы одна и та же книга не дублировалась у одного юзера
    add_index :yulib_books, [:user_id, :book_id], unique: true
  end
end