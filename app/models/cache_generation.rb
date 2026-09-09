require "securerandom"

class CacheGeneration
  include Mongoid::Document

  STATE_ID = "derived_views".freeze
  field :_id, type: String, default: STATE_ID
  field :epoch, type: String
  field :generation, type: Integer

  def self.current_version
    state = collection.find(_id: STATE_ID).first || update_state(
      "$setOnInsert" => { "epoch" => SecureRandom.uuid, "generation" => 0 }
    )
    version_for(state)
  end

  def self.advance!
    state = update_state(
      "$setOnInsert" => { "epoch" => SecureRandom.uuid },
      "$inc" => { "generation" => 1 }
    )
    version_for(state)
  end

  def self.update_state(update)
    collection.find(_id: STATE_ID).find_one_and_update(update, upsert: true, return_document: :after)
  rescue Mongo::Error::OperationFailure => error
    # Concurrent first-use upserts can race on the unique _id. Retry only that
    # collision, once, without upsert. Never swallow other MongoDB failures.
    raise unless error.code == 11000

    collection.find(_id: STATE_ID).find_one_and_update(update, return_document: :after)
  end
  private_class_method :update_state

  def self.version_for(state)
    epoch = state.fetch("epoch")
    generation = state.fetch("generation")
    unless epoch.is_a?(String) && !epoch.empty? && generation.is_a?(Integer) && generation >= 0
      raise "Invalid cache generation metadata"
    end

    "#{epoch}:#{generation}"
  end
  private_class_method :version_for
end
