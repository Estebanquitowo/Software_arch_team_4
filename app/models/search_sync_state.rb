require "digest"
require "securerandom"

# MongoDB owns both the recovery debt and coordination. No lease expiration:
# an abandoned lock requires an operator to confirm its owner has stopped.
class SearchSyncState
  include Mongoid::Document

  field :_id, type: String
  field :epoch, type: String
  field :dirty, type: Mongoid::Boolean, default: true
  field :revision, type: Integer, default: 0
  field :lock_token, type: String
  field :locked_at, type: Time

  def self.state_id
    index_uid = Book.respond_to?(:ms_index_uid) ? Book.ms_index_uid : "books_#{Rails.env}"
    Digest::SHA256.hexdigest([ ENV["MEILISEARCH_URL"], index_uid ].join("\n"))
  end

  def self.current
    id = state_id
    collection.find(_id: id).first || begin
      document = { "_id" => id, "epoch" => SecureRandom.uuid, "dirty" => true,
                   "revision" => 0, "lock_token" => nil, "locked_at" => nil }
      collection.insert_one(document)
      document
    end
  rescue Mongo::Error::OperationFailure => error
    raise unless error.code == 11000

    collection.find(_id: id).first
  end

  def self.mark_dirty!
    id = current.fetch("_id")
    previous = collection.find(_id: id).find_one_and_update(
      { "$set" => { "dirty" => true }, "$inc" => { "revision" => 1 } }, return_document: :before
    )
    previous.merge("dirty" => true, "revision" => previous.fetch("revision") + 1,
                   "was_dirty" => previous.fetch("dirty"))
  end

  def self.acquire(token)
    id = current.fetch("_id")
    collection.find(_id: id, lock_token: nil).find_one_and_update(
      { "$set" => { "lock_token" => token, "locked_at" => Time.now.utc } }, return_document: :after
    )
  end

  def self.publish_clean(token, revision)
    # Increment on publication too: search cache entries from before recovery
    # must never share an identity with the newly clean index.
    collection.find(_id: state_id, lock_token: token, revision: revision).find_one_and_update(
      { "$set" => { "dirty" => false }, "$inc" => { "revision" => 1 } }, return_document: :after
    )
  end

  def self.release(token)
    collection.find(_id: state_id, lock_token: token).update_one(
      "$set" => { "lock_token" => nil, "locked_at" => nil }
    ).modified_count == 1
  end

  def self.unlock_abandoned!(token)
    raise ArgumentError, "An explicit lock token is required" if token.blank?

    collection.find(_id: state_id, lock_token: token).update_one(
      "$set" => { "dirty" => true, "lock_token" => nil, "locked_at" => nil },
      "$inc" => { "revision" => 1 }
    ).modified_count == 1
  end
end
