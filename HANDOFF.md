# Project Context — Assignment 4 (Edge & Scale)

## Goal
Implement edge & scale for a Rails/MongoDB book review app per `ToDoList.md`.
Phases are executed in strict order; tests run after every change.

## Environment
- Rails 8.1.3.1 / Ruby 4.0.6 / MongoDB 8.0 + Mongoid 9.1
- **No ActiveRecord, no ActiveStorage** — Mongoid is schemaless; "migrations" = adding model fields in the model file
- No local Ruby/mongod on host; tests run only via Docker:
  `docker compose -p a4-test -f test/compose.yml build tests && docker compose -p a4-test -f test/compose.yml up --abort-on-container-exit tests`
- Test framework: minitest (`bin/rails test`); currently 79 tests, 423 assertions, all green
- Rubocop: run against host files inside the dev image with `-c .rubocop.yml` (host files don't auto-lint; container `rubocop` checks its baked copy, so mount host paths)

## Stack (preserved from Assignment 3)
- **Sessions**: Rails default CookieStore — already stateless/shared, no work needed for x3
- **Cache**: Redis (`CACHE_ENABLED` / `REDIS_URL`); `CacheService` + `CacheGeneration` in Mongo; falls back to MemoryStore
- **Search**: Meilisearch (`SEARCH_ENABLED` / `MEILISEARCH_URL`); `SearchSyncService` + `SearchSyncState`; falls back to Mongo regex
- **Image uploads**: `IMAGE_STORAGE_PATH` (default `/data/images`); `ImageStorage` service; served at `/images/<relative>` via `ImagesController`

## Progress
| Phase | Status |
|---|---|
| 1 — Understand | ✅ Analysis only, no code changes |
| 2 — Image Uploads | ✅ `ImageStorage`, book covers, author images, views, tests |
| 3 — Static Assets | 🔶 App side done: `SERVE_STATIC` flag toggles `public_file_server`; HAProxy serving/caching deferred to Phases 4–6 |
| 4–7 | HAProxy → TLS → edge statics → statelessness |
| 8–14 | Compose scaling, load-balancing, failure tests |
| 15–17 | Kubernetes with shared volumes |
| 18–33 | Load tests, docs, README, report |

## Key Decisions & Gotchas
1. **`Mongoid` has no `update_column`** — use `model.set(field: value)` (atomic, no callbacks)
2. **Glob route `get "images/*path"`** — Rails captures `.ext` as `params[:format]`, not `params[:path]`; use `request.path.delete_prefix("/images/")` instead
3. **Model validation required** — manual `errors.add` in controllers gets wiped by `save`/`update` validation lifecycle; use `attr_accessor :cover_image_upload` + `validate` callback
4. **`Rack::Mime.mime_type(ext, fallback)`** — NOT `Rack::Mime::MimeType.for`
5. **Uploaded images** live on a shared `image_data` volume in all compose files; `SERVE_STATIC` controls `config.public_file_server.enabled` (Phase 3)

## Conventions
- Work in `ToDoList.md` phase order; mark checkboxes as complete
- Tests after every change; run full suite via Docker
- Prefer env vars for all configuration; no hardcoded paths
- Don't invent endpoints, load-test numbers, or report content
- Reuse Assignment 3 cache/search code; never remove it

## Where to Look
| Need | File |
|---|---|
| Master task list | `ToDoList.md` (Phase N sections) |
| Deploy docs | `README.md`, `k8s/README.md` |
| Compose variants | `docker-compose{,.cache,.search,.full}.yml` |
| K8s overlays | `k8s/overlays/{base,cache,search,full}/` |
| Image storage | `app/services/image_storage.rb`, `app/controllers/images_controller.rb` |
| Static flag | `app/services/static_serve.rb`, `config/initializers/serve_static.rb` |
| Tests | `test/services/`, `test/controllers/` |

## How to Resume (new session)
1. Read `HANDOFF.md` (this file) first — it is the compact project context.
2. Read only the relevant `ToDoList.md` phase section before editing.
3. Verify tests are green before starting:
   `docker compose -p a4-test -f test/compose.yml build tests && docker compose -p a4-test -f test/compose.yml up --abort-on-container-exit tests`
4. Work the current phase below in order; mark `ToDoList.md` checkboxes and update this file's Progress table.

## Current / Next
- **Done:** Phase 1, Phase 2 (uploads), Phase 3 app side (`SERVE_STATIC`).
- **Pending (optional):** Plan A manual smoke test of Phase 2 uploads with real PNG/JPG (≤200×200).
  Run the base stack (`docker compose up -d --build`, app on `http://localhost:3000`), create an author (Profile Image) then a book (Cover Image + author), verify thumbnails on `/authors` and `/books`, `curl -I http://localhost:3000/images/<rel>`, and replace/remove via edit. Images live in the `image_data` volume at `/data/images` (inspect via `docker compose exec web ls -lR /data/images`).
- **Next phase:** Phase 4 — HAProxy (create config + container, frontend/backend, app not directly exposed). Phase 3.2 HAProxy checkboxes close here.

place images in tmp/photos/books and tmp /photos/author