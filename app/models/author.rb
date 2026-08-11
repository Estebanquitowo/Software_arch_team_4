class Author
  include Mongoid::Document
  include Mongoid::Timestamps
  field :name, type: String
  field :date_of_birth, type: Date
  field :country_of_origin, type: String
  field :short_description, type: String
end
