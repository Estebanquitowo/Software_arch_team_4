# Software Architecture - Team 4 (Rails + MongoDB)

Book review web application built with:

* Ruby 4.0.6
* Rails 8.1.3.1
* MongoDB 8.0
* [Mongoid](https://www.mongodb.com/docs/mongoid/current/quick-start-rails/) 9.1

## Prerequisites

* If on Windows 11:
    * WSL2 is needed, with Ubuntu>=24.04 LTS
    * Docker Desktop installed and running on Windows 11 (with WSL2 integration enabled).

## Local Development

1. Clone the repository and enter the directory:
    ```sh
    git clone https://github.com/Estebanquitowo/Software_arch_team_4
    cd Software_arch_team_4
    ```

1. Start the application stack:
    ```sh
    docker compose up -d --build
    ```

    The web server (service="web") will be accessible at http://localhost:3000. \
    The local MongoDB instance (service="mongodb") will run on port 27017.

1. Verify containers are running:
    ```sh
    docker compose ps
    ```

1. If running the app for the first time, populate it with:
    ```sh
    docker compose exec web bin/rails db:seed
    ```

    In order of populating the database, `seeds.rb` uses a [Hardcover.app](https://hardcover.app) API token. To obtain one:
    
    1. Create a Hardcover account.
    1. Go to the [account](https://hardcover.app/account/api) section inside the site.
    1. Copy the text block starting with the `'Bearer'` line, without including it.
    1. Paste it as a value for the `HARDCOVER_API_TOKEN` key inside `.env.example`.

## Workflow & Development Commands

Development can be done inside the Docker Containers. Effects of Rails and database commands ran inside them should persist even after containers are down. Commands ran this way must be prefixed with the `docker compose exec` string, as in all following examples.

### Database & Seeding
```sh
# Populate database with seed data
docker compose exec web bin/rails db:seed

# KEY DEBUGGING COMMAND: Access interactive MongoDB shell (mongosh)
docker compose exec mongodb mongosh
```

### Generators & Rails Console
```sh
# Open Rails interactive console
docker compose exec web bin/rails c

# Generate scaffolds (includes views, model and controller; essentialy batteries-included CRUD)
docker compose exec web bin/rails g scaffold Book title:string summary:text # remaining fields...
```

### Tests
```sh
# Run the test suite (connects to the test database in the mongodb container)
docker compose exec web bin/rails test
```

### Viewing Logs
```sh
# View live web application logs
docker compose logs -f web

# View live MongoDB container logs (not very useful xd)
docker compose logs -f mongodb
```

(Press Ctrl + C to exit log streams without stopping containers).

### Stopping & Rebuilding
```sh
# Stop containers (preserves database data)
docker compose down

# Rebuild containers (run whenever Gemfile or Dockerfile changes)
docker compose up -d --build

# Stop containers and wipe local database volumes (fresh start)
docker compose down -v
```
