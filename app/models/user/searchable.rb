module User::Searchable
  # Replace with a search engine like Meilisearch, ElasticSearch, or pg_search to provide better results
  # Using arel matches allows for database agnostic like queries

  extend ActiveSupport::Concern

  class_methods do
    def search(query)
      q = sanitize_sql_like(query.to_s)

      # Prefer generated `users.name` column when present; otherwise, fallback to a
      # portable expression that concatenates first and last name per adapter.
      if column_names.include?("name")
        where(arel_table[:name].matches("%#{q}%"))
      else
        adapter = connection.adapter_name
        case adapter
        when "PostgreSQL", "PostGIS"
          where("COALESCE(#{table_name}.first_name, '') || ' ' || COALESCE(#{table_name}.last_name, '') ILIKE ?", "%#{q}%")
        when "Trilogy", "Mysql2"
          where("LOWER(CONCAT_WS(' ', #{table_name}.first_name, #{table_name}.last_name)) LIKE ?", "%#{q.downcase}%")
        else
          # Generic fallback using LOWER and string concatenation with a space.
          where("LOWER(#{table_name}.first_name || ' ' || #{table_name}.last_name) LIKE ?", "%#{q.downcase}%")
        end
      end
    end
  end
end
