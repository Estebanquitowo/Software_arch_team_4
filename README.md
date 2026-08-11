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

## Workflow & Development Commands

Development can be done inside the Docker Containers. Effects of Rails and database commands ran inside them should persist even after containers are down. Commands ran this way must be prefixed with the `docker compose exec` string, as in all following examples.

### Database & Seeding
```sh
# Populate database with seed data (there's none yet)
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