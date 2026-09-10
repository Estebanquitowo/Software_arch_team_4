# In-memory SDK boundary for deterministic task failures and interleavings.
# A separate scenario uses Meilisearch 1.12 with its actual async task queue.
class SearchDouble
  Task = Struct.new(:status) do
    def await(*)
      self
    end
  end

  attr_accessor :on_clear, :on_add, :failure_stage
  attr_reader :documents, :calls

  def initialize
    @documents = {}
    @calls = []
    @settings = {}
  end

  def index(*)
    self
  end

  def fetch_info
    {}
  end

  def settings
    @settings
  end

  def update_settings(settings)
    @settings = settings.transform_keys(&:to_s)
    task(:settings)
  end

  def add_documents(documents)
    documents.each { |document| @documents[document.fetch("id")] = document }
    on_add&.call
    task(:add)
  end

  def delete_document(id)
    @documents.delete(id)
    task(:delete)
  end

  def delete_all_documents
    @documents.clear
    on_clear&.call
    task(:clear)
  end

  def tasks(*)
    { "results" => [] }
  end

  private

  def task(stage)
    @calls << stage
    Task.new(failure_stage == stage ? "failed" : "succeeded")
  end
end
