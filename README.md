# script-certification-management-system-52-62

This workspace contains the certification_service_db PostgreSQL container for the Script Certification Management System.

Quick start:
- Run the database startup script (will initialize Postgres, create DB/user and apply migrations automatically):
  ./certification_service_db/startup.sh

- Connection info is written to:
  script-certification-management-system-52-62/certification_service_db/db_connection.txt

- A simple DB viewer is available (after sourcing env):
  cd certification_service_db/db_visualizer
  source postgres.env
  npm install
  npm start
  Then open http://localhost:3000 and select Postgres.

Migrations:
- SQL migration files are in certification_service_db/migrations
- On container startup, startup.sh applies any new *.sql files in lexicographical order.
- Applied migrations are tracked in the schema_migrations table.
- To add a new migration, create a file like 002_add_something.sql in the migrations folder; it will be picked up on next start.