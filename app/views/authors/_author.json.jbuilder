json.extract! author, :id, :name, :date_of_birth, :country_of_origin, :short_description, :created_at, :updated_at
json.url author_url(author, format: :json)
