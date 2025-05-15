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
*   `SECRET_KEY_BASE`: A secret key used by Phoenix for signing session cookies and other security features. Generate one using `docker compose run --rm app mix phx.gen.secret`.

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

These files are mounted into the respective containers by `docker compose.yml`.

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
    Create a `.env` file in the project root (e.g., by copying an example if provided) and fill in your desired configuration values, especially database credentials, `BTCPAY_WEBHOOK_SECRET`, and `SECRET_KEY_BASE`. If you don't have a `SECRET_KEY_BASE`, you can generate one after the initial `app` service build (see step 8, then update your `.env` file and restart the `app` service if needed, or generate it before first `docker compose up` if base Elixir image is sufficient).

3.  **Ensure a clean state (optional, recommended for first run or troubleshooting):**
    This command will stop any running services and remove associated Docker volumes (including database data).
    ```bash
    docker compose down -v
    ```

4.  **Start the Primary PostgreSQL Database:**
    This command builds the images if necessary and starts the `postgres_primary` service.
    ```bash
    docker compose up -d --build postgres_primary
    ```

5.  **Wait for Primary Database Initialization:**
    Give the primary database a few moments (e.g., 15-30 seconds) to initialize. You can check its logs:
    ```bash
    docker compose logs postgres_primary
    ```
    Look for a line like `database system is ready to accept connections`.

6.  **Create Replication User on Primary:**
    Execute the following command to create the replication user. Use the `POSTGRES_REPLICATION_USER` and `POSTGRES_REPLICATION_PASSWORD` you defined in your `.env` file (or the defaults `replicator`/`replpassword`).
    ```bash
    docker compose exec -T postgres_primary psql -U ${PRIMARY_DB_USER:-postgres} -d ${PRIMARY_DB_NAME:-btcpay_tracker_dev} \
      -c "CREATE USER ${POSTGRES_REPLICATION_USER:-replicator} WITH REPLICATION ENCRYPTED PASSWORD '${POSTGRES_REPLICATION_PASSWORD:-replpassword}';"
    ```
    *Note: If you re-run this after the user is created, it will show an error like "role already exists," which is fine.*

7.  **Create Replication Slot on Primary:**
    The replica will use a named replication slot. Create it on the primary:
    ```bash
    docker compose exec -T postgres_primary psql -U ${PRIMARY_DB_USER:-postgres} -d ${PRIMARY_DB_NAME:-btcpay_tracker_dev} \
      -c "SELECT * FROM pg_create_physical_replication_slot('replication_slot_slave1');"
    ```
    *Note: If re-running, this may show "replication slot already exists," which is fine.* The slot name `replication_slot_slave1` is hardcoded in the `postgres_replica` service's command in `docker compose.yml`.

8.  **Fetch Application Dependencies:**
    Before starting the `app` service, ensure its Elixir dependencies are fetched. This command will also build the `app` image if it hasn't been built yet or if its Dockerfile configuration has changed (e.g., `mix.exs` was updated).
    ```bash
    docker compose run --rm app mix deps.get
    ```

9.  **Start All Other Services (Nginx, Replica, App):**
    Now, start `nginx`, `postgres_replica`, and the Elixir `app` service. It's recommended to ensure images are up-to-date, especially if you made changes to Dockerfiles or application code.
    ```bash
    docker compose up -d --build nginx postgres_replica app
    ```
    The `postgres_replica` service will perform a base backup from the primary and then start streaming. The `nginx` service will act as the entry point.
    The `app` service, as defined in `docker compose.yml` (typically with `command: sh -c "mix ecto.setup && mix phx.server"`), will attempt to perform initial database setup (including migrations) and then start the Phoenix server.

    If you haven't generated `SECRET_KEY_BASE` yet and included it in your `.env` file, the `app` service might fail to start or run correctly. You can generate it with:
    ```bash
    docker compose run --rm app mix phx.gen.secret
    ```
    Copy the output into your `.env` file for the `SECRET_KEY_BASE` variable. Then, restart the `app` service if it was already started and failed: `docker compose restart app` or re-run the `docker compose up -d --build app` command.

10. **Verify Database Setup & Migrations:**
    After the `app` service starts, check its logs to ensure the initial `mix ecto.setup` (from its command) completed successfully:
    ```bash
    docker compose logs app
    ```
    If `mix ecto.setup` failed, or for applying new migrations later, you can explicitly run migrations by targeting the primary repository:
    ```bash
    docker compose exec app mix ecto.migrate -r BtcpayTracker.Repo
    ```
    *(Note: The original `docker compose exec app sh -c "mix ecto.setup"` command previously listed here is generally handled by the app service's startup command. Running `mix ecto.migrate -r BtcpayTracker.Repo` is preferred for explicit migration control after the app is up or if initial setup via service command fails.)*

## Verification

1.  **Check Primary Logs:**
    ```bash
    docker compose logs postgres_primary
    ```
    Should show normal operation.

2.  **Check Replica Logs:**
    ```bash
    docker compose logs postgres_replica
    ```
    Look for:
    *   Messages indicating `pg_basebackup` completed.
    *   `LOG:  entering standby mode`
    *   `LOG:  database system is ready to accept read-only connections`
    *   `LOG:  started streaming WAL from primary ...`

3.  **Test Replication Manually (Optional):**
    *   **Connect to Primary and Insert Data:**
        ```bash
        docker compose exec -T postgres_primary psql -U ${PRIMARY_DB_USER:-postgres} -d ${PRIMARY_DB_NAME:-btcpay_tracker_dev} \
          -c "CREATE TABLE IF NOT EXISTS replication_test (id INT PRIMARY KEY); INSERT INTO replication_test (id) VALUES (EXTRACT(EPOCH FROM NOW())::INT) ON CONFLICT (id) DO NOTHING;"
        ```
    *   **Connect to Replica and Read Data:**
        Wait a few seconds, then:
        ```bash
        docker compose exec -T postgres_replica psql -U ${PRIMARY_DB_USER:-postgres} -d ${PRIMARY_DB_NAME:-btcpay_tracker_dev} -h localhost \
          -c "SELECT * FROM replication_test ORDER BY id DESC LIMIT 1;"
        ```
        You should see the inserted data.
    *   **Attempt Write on Replica (should fail):**
        ```bash
        docker compose exec -T postgres_replica psql -U ${PRIMARY_DB_USER:-postgres} -d ${PRIMARY_DB_NAME:-btcpay_tracker_dev} -h localhost \
          -c "INSERT INTO replication_test (id) VALUES (999);"
        ```
        This should result in an error like `ERROR: cannot execute INSERT in a read-only transaction`.

## Accessing the Application

The application is accessed via the Nginx reverse proxy:

*   **Dashboard**: `http://localhost/dashboard`
*   **Webhook Endpoint**: `http://localhost/api/webhooks/btcpay/events`

HTTPS is expected to be handled by an external service like Cloudflare Tunnels, which would terminate SSL and forward traffic to Nginx on port 80. Your BTCPayServer webhook should be configured to point to the HTTPS URL provided by Cloudflare Tunnels.

## Exposing the Application with Cloudflare Tunnel

Cloudflare Tunnel provides a secure way to expose your locally running application to the internet without opening firewall ports. It establishes an outbound-only connection to Cloudflare's network.

### Prerequisites

*   A Cloudflare account.
*   Your domain added to Cloudflare.
*   `cloudflared` daemon installed on the server where your Docker application is running. Installation instructions can be found on the [Cloudflare developers website](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/).

### Setup Steps

1.  **Login to Cloudflare:**
    Open a terminal on your server and authenticate `cloudflared` with your Cloudflare account:
    ```bash
    cloudflared login
    ```
    This will open a browser window asking you to log in and authorize the domain you want to use.

2.  **Create a Tunnel:**
    Create a tunnel for your application. Replace `<your-tunnel-name>` with a descriptive name (e.g., `btcpay-app-tunnel`).
    ```bash
    cloudflared tunnel create <your-tunnel-name>
    ```
    This command will output a tunnel ID and create a credentials file (e.g., `~/.cloudflared/<TUNNEL-ID>.json` or `/root/.cloudflared/<TUNNEL-ID>.json`). Note down the tunnel ID.

3.  **Configure DNS:**
    In your Cloudflare dashboard, navigate to your domain's DNS settings. Create a `CNAME` record:
    *   **Type**: `CNAME`
    *   **Name**: The subdomain you want to use (e.g., `btcpaytracker` for `btcpaytracker.yourdomain.com`).
    *   **Target**: Your tunnel's hostname, which is `<TUNNEL-ID>.cfargotunnel.com`. Replace `<TUNNEL-ID>` with the ID from the previous step.
    *   **Proxy status**: Ensure it's set to "Proxied" (orange cloud).

4.  **Create a Configuration File (for running as a service):**
    To run `cloudflared` as a service, create a configuration file. On Linux, this is typically at `/etc/cloudflared/config.yml`.
    You'll need root/sudo privileges to create and edit this file.

    ```yaml
    # /etc/cloudflared/config.yml

    tunnel: <your-tunnel-name> # Or use the Tunnel ID directly
    credentials-file: /root/.cloudflared/<TUNNEL-ID>.json # Adjust path if you ran 'create' as non-root

    ingress:
      # Rule for your application. This points to your Nginx container.
      - hostname: your-chosen-cname.yourdomain.com # e.g., btcpaytracker.yourdomain.com
        service: http://localhost:80 # Nginx listens on port 80
      # Catch-all rule to return 404 for unconfigured hostnames
      - service: http_status:404
    ```
    **Important:**
    *   Replace `<your-tunnel-name>` with the name you chose (or use the Tunnel ID directly with `tunnel: <TUNNEL-ID>`).
    *   Replace `<TUNNEL-ID>.json` with your actual tunnel ID.
    *   The `credentials-file` path should point to the `.json` file generated when you created the tunnel. If you ran `cloudflared tunnel create` as a non-root user, it might be in that user's home directory (e.g., `/home/youruser/.cloudflared/<TUNNEL-ID>.json`). The service usually runs as `cloudflared` or a similar user, so ensure this user can read the credentials file, or move the file to `/etc/cloudflared/` and update the path.
    *   Replace `your-chosen-cname.yourdomain.com` with the actual public hostname you configured in Cloudflare DNS.

5.  **Install and Run `cloudflared` as a Service (Linux/Debian):**
    If you haven't already, stop any manually running `cloudflared tunnel run` processes.
    ```bash
    sudo cloudflared service install
    sudo systemctl enable cloudflared
    sudo systemctl start cloudflared
    ```

6.  **Verify the Service:**
    Check the status of the service:
    ```bash
    sudo systemctl status cloudflared
    ```
    View logs (especially if troubleshooting):
    ```bash
    sudo journalctl -u cloudflared -f
    ```

7.  **Update BTCPayServer Webhook:**
    Once your application is accessible via the Cloudflare Tunnel URL (e.g., `https://your-chosen-cname.yourdomain.com`), update your BTCPayServer webhook configuration to point to this new HTTPS URL, specifically the webhook endpoint: `https://your-chosen-cname.yourdomain.com/api/webhooks/btcpay/events`.

## Stopping the Services

*   To stop all services:
    ```bash
    docker compose down
    ```
*   To stop services and remove data volumes (deletes all database data):
    ```bash
    docker compose down -v
    ```

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
