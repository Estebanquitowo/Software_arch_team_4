class AuthorDetailsSeeder
  def self.call
    Author.each do |author|
      attributes = HardcoverSeeder.with_fallback_author_details(
        date_of_birth: author.date_of_birth,
        country_of_origin: author.country_of_origin.presence,
        short_description: author.short_description.presence
      )

      updates = attributes.slice(:date_of_birth, :country_of_origin, :short_description)
                          .reject { |field, value| author.public_send(field) == value }

      author.update!(updates) if updates.any?
    end
  end
end
