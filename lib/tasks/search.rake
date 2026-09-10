namespace :search do
  desc "Rebuild the Books index from MongoDB and publish clean only after verified success"
  task reconcile: :environment do
    result = SearchSyncService.reconcile!
    puts "[Search] Reconciliation: #{result}"
    abort "[Search] Index remains dirty; inspect service logs/state" unless %i[clean disabled].include?(result)
  end

  desc "Reconcile all books, including documents deleted during an outage"
  task reindex: :reconcile

  desc "Clear Meilisearch index"
  task clear: :environment do
    result = SearchSyncService.clear!
    puts "[Search] Clear: #{result}; index remains dirty until reconciliation"
    abort "[Search] Clear did not complete" unless %i[cleared disabled].include?(result)
  end

  desc "Release an abandoned lock only after confirming the owner has stopped"
  task :unlock, [ :token ] => :environment do |_task, args|
    abort "Set SEARCH_SYNC_OWNER_STOPPED=yes after verifying the owner is stopped" unless ENV["SEARCH_SYNC_OWNER_STOPPED"] == "yes"
    abort "Supply the exact abandoned lock token" if args[:token].blank?
    abort "Lock token did not match; nothing changed" unless SearchSyncState.unlock_abandoned!(args[:token])
    puts "[Search] Lock released; index remains dirty. Run search:reconcile."
  end
end

namespace :cache do
  desc "Invalidate derived cache by advancing its MongoDB generation (no Redis flush)"
  task clear: :environment do
    CacheService.clear
    puts "[Cache] Generation advanced; older entries will miss and expire by TTL"
  end
end
