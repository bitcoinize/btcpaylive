# BTCPay Tracker - Webhook Service & Real-time Dashboard

This project implements a service to receive webhook notifications from BTCPayServer for invoice events, store them in a PostgreSQL database (with a read replica), and display them on a real-time dashboard.

## Prerequisites

*   Docker
*   Docker Compose

## Configuration

This application uses environment variables for configuration. You can set these in a `.env` file in the project root. Key variables include:

*   `APP_PORT`: Port for the Elixir/Phoenix application (default: `4000`).
*   `PRIMARY_DB_USER`, `PRIMARY_DB_PASS`, `PRIMARY_DB_NAME`: Credentials for the primary PostgreSQL database.
*   `PRIMARY_DB_EXPOSED_PORT`: Exposed host port for the primary PostgreSQL database (default: `5432`).
*   `POSTGRES_REPLICATION_USER`, `POSTGRES_REPLICATION_PASSWORD`: Credentials for the PostgreSQL replication user (used by the replica to connect to the primary).
*   `REPLICA_DB_EXPOSED_PORT`: Exposed host port for the replica PostgreSQL database (default: `5433`).
*   `BTCPAY_WEBHOOK_SECRET`: The shared secret used to validate incoming webhooks from BTCPayServer.
*   `SECRET_KEY_BASE`: A secret key used by Phoenix for signing session cookies and other security features. Generate one using `docker-compose run --rm app mix phx.gen.secret`.

**Example `.env` file:**
```env
APP_PORT=4000

PRIMARY_DB_USER=postgres
PRIMARY_DB_PASS=mysecretpassword
PRIMARY_DB_NAME=btcpay_tracker_dev
PRIMARY_DB_EXPOSED_PORT=5432

# User for replication (must match what's created in primary DB)
POSTGRES_REPLICATION_USER=replicator
POSTGRES_REPLICATION_PASSWORD=replpassword

REPLICA_DB_EXPOSED_PORT=5433

# BTCPayServer Webhook Secret
BTCPAY_WEBHOOK_SECRET=your_btcpay_webhook_secret_here

# Phoenix Secret Key Base
SECRET_KEY_BASE=your_generated_secret_key_base_here
```

### PostgreSQL Configuration Files

The PostgreSQL primary and replica have specific configuration files located in:
*   `docker/postgres/primary/postgresql.conf`: Main configuration for the primary, enabling replication features (`wal_level = replica`, etc.).
*   `docker/postgres/primary/pg_hba.conf`: Host-based authentication rules for the primary, allowing replication connections from the replica user.
*   `docker/postgres/replica/postgresql.conf`: Main configuration for the replica.

These files are mounted into the respective containers by `docker-compose.yml`.

### Nginx Configuration
The Nginx service acts as a reverse proxy for the Phoenix application. Its configuration is located at:
*   `docker/nginx/conf.d/default.conf`

Nginx listens on port 80 (HTTP) and forwards requests to the Phoenix application. HTTPS termination is expected to be handled by an external service like Cloudflare Tunnels, which would point to Nginx on port 80.

## Initial Setup & Deployment

1.  **Clone the repository:**
    ```bash
    git clone <repository_url>
    cd <repository_name>
    ```

2.  **Create and populate `.env` file:**
    Create a `.env` file in the project root (e.g., by copying an example if provided) and fill in your desired configuration values, especially database credentials, `BTCPAY_WEBHOOK_SECRET`, and `SECRET_KEY_BASE`. If you don't have a `SECRET_KEY_BASE`, you can generate one after the initial `app` service build (see step 8, then update your `.env` file and restart the `app` service if needed, or generate it before first `docker-compose up` if base Elixir image is sufficient).

3.  **Ensure a clean state (optional, recommended for first run or troubleshooting):**
    This command will stop any running services and remove associated Docker volumes (including database data).
    ```bash
    docker-compose down -v
    ```

4.  **Start the Primary PostgreSQL Database:**
    This command builds the images if necessary and starts the `postgres_primary` service.
    ```bash
    docker-compose up -d --build postgres_primary
    ```

5.  **Wait for Primary Database Initialization:**
    Give the primary database a few moments (e.g., 15-30 seconds) to initialize. You can check its logs:
    ```bash
    docker-compose logs postgres_primary
    ```
    Look for a line like `database system is ready to accept connections`.

6.  **Create Replication User on Primary:**
    Execute the following command to create the replication user. Use the `POSTGRES_REPLICATION_USER` and `POSTGRES_REPLICATION_PASSWORD` you defined in your `.env` file (or the defaults `replicator`/`replpassword`).
    ```bash
    docker-compose exec -T postgres_primary psql -U ${PRIMARY_DB_USER:-postgres} -d ${PRIMARY_DB_NAME:-btcpay_tracker_dev} \
      -c "CREATE USER ${POSTGRES_REPLICATION_USER:-replicator} WITH REPLICATION ENCRYPTED PASSWORD '${POSTGRES_REPLICATION_PASSWORD:-replpassword}';"
    ```
    *Note: If you re-run this after the user is created, it will show an error like "role already exists," which is fine.*

7.  **Create Replication Slot on Primary:**
    The replica will use a named replication slot. Create it on the primary:
    ```bash
    docker-compose exec -T postgres_primary psql -U ${PRIMARY_DB_USER:-postgres} -d ${PRIMARY_DB_NAME:-btcpay_tracker_dev} \
      -c "SELECT * FROM pg_create_physical_replication_slot('replication_slot_slave1');"
    ```
    *Note: If re-running, this may show "replication slot already exists," which is fine.* The slot name `replication_slot_slave1` is hardcoded in the `postgres_replica` service's command in `docker-compose.yml`.

8.  **Start All Other Services (Nginx, Replica, App):**
    Now, start the `nginx`, `postgres_replica`, and the Elixir `app` service.
    ```bash
    docker-compose up -d --build nginx postgres_replica app
    ```
    The `postgres_replica` service will perform a base backup from the primary and then start streaming. The `nginx` service will act as the entry point.
    If you haven't generated `SECRET_KEY_BASE` yet, you can do so now:
    ```bash
    docker-compose run --rm app mix phx.gen.secret
    ```
    Copy the output into your `.env` file for the `SECRET_KEY_BASE` variable. You might need to restart the `app` service (`docker-compose restart app`) for it to pick up the new secret if it was already running.

9.  **Setup Application Database (Migrations):**
    Once the `app` service is running and the primary database is available, run the Ecto setup command to create tables and run migrations for the application.
    The initial setup can be done with:
    ```bash
    docker-compose exec app sh -c "mix ecto.setup"
    ```
    For subsequent migrations, or if `ecto.setup` causes issues due to the read-only replica, it is recommended to run migrations by explicitly targeting the primary repository:
    ```bash
    docker-compose run --rm app mix ecto.migrate -r BtcpayTracker.Repo
    ```
    This command ensures that migration operations are only attempted on the `postgres_primary` database and do not affect the `postgres_replica`.

## Verification

1.  **Check Primary Logs:**
    ```bash
    docker-compose logs postgres_primary
    ```
    Should show normal operation.

2.  **Check Replica Logs:**
    ```bash
    docker-compose logs postgres_replica
    ```
    Look for:
    *   Messages indicating `pg_basebackup` completed.
    *   `LOG:  entering standby mode`
    *   `LOG:  database system is ready to accept read-only connections`
    *   `LOG:  started streaming WAL from primary ...`

3.  **Test Replication Manually (Optional):**
    *   **Connect to Primary and Insert Data:**
        ```bash
        docker-compose exec -T postgres_primary psql -U ${PRIMARY_DB_USER:-postgres} -d ${PRIMARY_DB_NAME:-btcpay_tracker_dev} \
          -c "CREATE TABLE IF NOT EXISTS replication_test (id INT PRIMARY KEY); INSERT INTO replication_test (id) VALUES (EXTRACT(EPOCH FROM NOW())::INT) ON CONFLICT (id) DO NOTHING;"
        ```
    *   **Connect to Replica and Read Data:**
        Wait a few seconds, then:
        ```bash
        docker-compose exec -T postgres_replica psql -U ${PRIMARY_DB_USER:-postgres} -d ${PRIMARY_DB_NAME:-btcpay_tracker_dev} -h localhost \
          -c "SELECT * FROM replication_test ORDER BY id DESC LIMIT 1;"
        ```
        You should see the inserted data.
    *   **Attempt Write on Replica (should fail):**
        ```bash
        docker-compose exec -T postgres_replica psql -U ${PRIMARY_DB_USER:-postgres} -d ${PRIMARY_DB_NAME:-btcpay_tracker_dev} -h localhost \
          -c "INSERT INTO replication_test (id) VALUES (999);"
        ```
        This should result in an error like `ERROR: cannot execute INSERT in a read-only transaction`.

## Accessing the Application

The application is accessed via the Nginx reverse proxy:

*   **Dashboard**: `http://localhost/dashboard`
*   **Webhook Endpoint**: `http://localhost/api/webhooks/btcpay/events`

HTTPS is expected to be handled by an external service like Cloudflare Tunnels, which would terminate SSL and forward traffic to Nginx on port 80. Your BTCPayServer webhook should be configured to point to the HTTPS URL provided by Cloudflare Tunnels.

## Stopping the Services

*   To stop all services:
    ```bash
    docker-compose down
    ```
*   To stop services and remove data volumes (deletes all database data):
    ```bash
    docker-compose down -v
    ```

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
