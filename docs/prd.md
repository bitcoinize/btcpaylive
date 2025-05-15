# Product Requirements Document: BTCPayServer Webhook Service & Real-time Dashboard

## 1. Introduction

### 1.1 Purpose
This document outlines the requirements for a system that receives webhook notifications from BTCPayServer for settled invoices, records these transactions in a PostgreSQL database (with a read replica), and displays them on a real-time dashboard.

### 1.2 Project Goal
To create a reliable and scalable system for tracking and visualizing cryptocurrency transactions processed via BTCPayServer in real-time, supporting the "World Record Transaction Tracker" initiative. The system will ensure data integrity and provide immediate insights into transaction activity.

### 1.3 Definitions
*   **BTCPayServer**: The self-hosted cryptocurrency payment processor.
*   **Webhook**: An automated message sent from BTCPayServer when an invoice is settled.
*   **API**: The Elixir/Erlang application that will receive webhooks and serve dashboard data.
*   **Primary DB**: The main PostgreSQL database instance used for writing transaction data.
*   **Read Replica DB**: A PostgreSQL database instance that replicates data from the Primary DB, used for read-only queries by the dashboard.
*   **Dashboard**: A web interface displaying real-time transaction metrics.
*   **Settled Invoice**: An invoice for which payment has been confirmed on the blockchain or Lightning Network.
*   **Pending Invoice**: An invoice that has been created in BTCPayServer but not yet fully paid or settled. The system will create an initial record for it.

## 2. System Architecture

### 2.1 Overview
The system will consist of the following components:
1.  **BTCPayServer (External)**: Configured to send webhook notifications for settled invoices to our API.
2.  **Webhook Ingestion API (Elixir/Phoenix)**:
    *   Receives webhook POST requests from BTCPayServer.
    *   Validates the webhook signature.
    *   Parses the invoice data.
    *   Writes transaction details to the Primary PostgreSQL database.
3.  **PostgreSQL Database (Primary)**:
    *   Stores all settled transaction data.
    *   Configured for write operations from the API.
4.  **PostgreSQL Database (Read Replica)**:
    *   Replicates data from the Primary DB.
    *   Used for read operations by the Dashboard Service to minimize load on the Primary DB.
5.  **Dashboard Service (Elixir/Phoenix)**:
    *   Provides API endpoints or Phoenix LiveView/Channels to serve aggregated and individual transaction data to the dashboard frontend.
    *   Queries data from the Read Replica DB.
6.  **Real-time Dashboard Frontend**:
    *   A web interface that connects to the Dashboard Service.
    *   Displays metrics like total transactions, total value, average transaction amount, and transaction type breakdown in real-time.
7.  **Docker Compose**: Orchestrates the deployment and networking of the Elixir API, PostgreSQL Primary, and PostgreSQL Read Replica.

### 2.2 Data Flow
1.  Merchant's BTCPayServer instance creates an invoice.
2.  BTCPayServer sends an `InvoiceCreated` webhook (HTTP POST) to a predefined endpoint on the Elixir API.
3.  The Elixir API verifies the `BTCPAY-SIG` header to authenticate the webhook.
4.  The API parses the `InvoiceCreated` payload and creates a new transaction record in the `transactions` table in the Primary PostgreSQL database with a "pending" status and stores the initial details (e.g., `invoiceId`, `orderId`, `amount_fiat`, `currency_fiat`, `created_at_webhook_timestamp`).
5.  When a payment is detected for the invoice, BTCPayServer sends an `InvoicePaymentSettled` webhook.
6.  The Elixir API verifies the signature, parses the `InvoicePaymentSettled` payload, and updates the existing transaction record with payment-specific details (e.g., `amount_crypto`, `currency_crypto`, `payment_method`, `payment_settled_at_webhook_timestamp`). The status might be updated to "processing_payment" or similar.
7.  Once the invoice is fully settled in BTCPayServer, it sends an `InvoiceSettled` webhook.
8.  The Elixir API verifies the signature, parses the `InvoiceSettled` payload, and updates the transaction record to "settled" status, capturing the final `final_settled_at_webhook_timestamp` and any other relevant finalization details.
9.  The Primary PostgreSQL database replicates the new and updated data to the Read Replica.
10. The Dashboard Frontend requests data from the Dashboard Service (Elixir/Phoenix).
11. The Dashboard Service queries the Read Replica PostgreSQL database.
12. The Dashboard Service sends the data to the Frontend, which updates in real-time (e.g., via Phoenix LiveView, WebSockets, or polling).

## 3. Core Features

### F1: Webhook Ingestion & Validation
*   **F1.1**: API shall expose an HTTPS endpoint (e.g., `/webhooks/btcpay/events`) to receive POST requests from BTCPayServer for various invoice-related events.
*   **F1.2**: API shall validate incoming webhooks using the `BTCPAY-SIG` header and a pre-configured shared secret (HMAC-SHA256). Unauthenticated requests shall be rejected.
*   **F1.3**: API shall handle the following BTCPayServer event types:
    *   `InvoiceCreated`: To create an initial record for the invoice with a "pending" status.
    *   `InvoicePaymentSettled`: To update the record with cryptographic payment details (amount, currency, payment method) once a payment is confirmed.
    *   `InvoiceSettled`: To mark the invoice record as "settled" and record the final settlement time.
    *   Other event types may be logged for diagnostic purposes but not processed for core data aggregation initially.
* **F1.4**: Example Webhook POST payloads:

```
{
  "deliveryId": "QoHyRx5NW8Q8BVkYSN8mK9",
  "webhookId": "9ZCwf9BzRzuQntm4LGp6QY",
  "originalDeliveryId": "QoHyRx5NW8Q8BVkYSN8mK9",
  "isRedelivery": false,
  "type": "InvoiceCreated",
  "timestamp": 1747317959,
  "storeId": "Fpuu6SqcR5RUF1o3eVjrpTKmNNmZWBd5Vadrz9f6RnQT",
  "invoiceId": "L1mcYRTBuuMQiS7nyju93v",
  "metadata": {
    "itemDesc": "Test USD",
    "orderId": "5JZK84xQDhAng9vWcmG3KY",
    "orderUrl": "https://btcpayserver.bitcoinjungle.app/apps/CtvxRDBisk5nfKiZqojzxqAov6G/pos",
    "posData": {
      "subTotal": 0.02,
      "total": 0.02,
      "amounts": [
        0.02
      ],
      "cart": []
    },
    "receiptData": {
      "Cart": {
        "Manual entry 1": "$0.02"
      },
      "Subtotal": "$0.02",
      "Total": "$0.02"
    }
  }
}
```

```
{
    "afterExpiration": false,
    "paymentMethod": "BTC-LightningNetwork",
    "payment": {
      "id": "f5aa8159d45edeff9a71da5da265364f0fe422579e4cd78016d97988278eedc1",
      "receivedDate": 1747339570,
      "value": "0.0000002",
      "fee": "0.0",
      "status": "Settled",
      "destination": "lnbc200n1p5ztax8pp57k4gzkw5tm00lxn3mfw6yefkfu87ggjhnexd0qqkm9ucsfuwahqsdzj2pskjepqw3hjq4r9wd6zq42ngsszsnmjv3jhygzfgsazqd22tf9nsdrc29zxsstwvuuhv4mrd4rnxj6e9ycqzzsxqzursp5jmku6ytm0mnuzjeypl2ehv28qr6kadur2ed8yr9wkuspzfpel7ks9qxpqysgqrrfq6r508n966dhpfjdk6lhfjjwcglm0xp3l6l3yh6gadz7sdd8jsnn28rsrcz8jntyhq56uryrj2sucwg2s4a2sh25zyvpcvhvr8nsp3qhdlq"
    },
    "deliveryId": "C8upTfMpNdWTQE7j7dsGux",
    "webhookId": "9ZCwf9BzRzuQntm4LGp6QY",
    "originalDeliveryId": "C8upTfMpNdWTQE7j7dsGux",
    "isRedelivery": false,
    "type": "InvoicePaymentSettled",
    "timestamp": 1747317970,
    "storeId": "Fpuu6SqcR5RUF1o3eVjrpTKmNNmZWBd5Vadrz9f6RnQT",
    "invoiceId": "L1mcYRTBuuMQiS7nyju93v",
    "metadata": {
      "orderId": "5JZK84xQDhAng9vWcmG3KY",
      "posData": {
        "cart": [],
        "total": 0.02,
        "amounts": [
          0.02
        ],
        "subTotal": 0.02
      },
      "itemDesc": "Test USD",
      "orderUrl": "https://btcpayserver.bitcoinjungle.app/apps/CtvxRDBisk5nfKiZqojzxqAov6G/pos",
      "receiptData": {
        "Cart": {
          "Manual entry 1": "$0.02"
        },
        "Total": "$0.02",
        "Subtotal": "$0.02"
      }
    }
  }
```


```
{
  manuallyMarked: false,
  overPaid: false,
  deliveryId: 'JaEp4EVAgQeuyV4HWky7tU',
  webhookId: '4vairVVXnQWn43wUSacxLA',
  originalDeliveryId: 'JaEp4EVAgQeuyV4HWky7tU',
  isRedelivery: false,
  type: 'InvoiceSettled',
  timestamp: 1747315881,
  storeId: 'Fpuu6SqcR5RUF1o3eVjrpTKmNNmZWBd5Vadrz9f6RnQT',
  invoiceId: '2Vj6s2sPAFwxu6GHadaTzh',
  metadata: {
    orderId: 'RBfQgmM57zi6ApXtrBcRbn',
    posData: { cart: [], total: 0.25, amounts: [Array], subTotal: 0.25 },
    itemDesc: 'Test USD',
    orderUrl: 'https://btcpayserver.bitcoinjungle.app/apps/CtvxRDBisk5nfKiZqojzxqAov6G/pos',
    receiptData: { Cart: [Object], Total: '$0.25', Subtotal: '$0.25' }
  }
}
```

### F2: Data Persistence
*   **F2.1**: A PostgreSQL table (e.g., `transactions`) shall be created to store transaction details.
*   **F2.2**: The schema for the `transactions` table should include (at minimum, types TBD):
    *   `id` (Primary Key, `:binary_id`, autogenerated UUID)
    *   `btcpay_invoice_id` (TEXT, unique, from BTCPayServer)
    *   `btcpay_order_id` (TEXT, nullable, if provided by BTCPayServer metadata)
    *   `store_id` (TEXT, nullable, indexed, from BTCPayServer `storeId` in webhook)
    *   `status` (TEXT, e.g., "pending", "processing_payment", "settled", default: "pending")
    *   `amount_crypto` (NUMERIC, e.g., BTC amount, populated from `InvoicePaymentSettled`)
    *   `currency_crypto` (TEXT, e.g., "BTC", populated from `InvoicePaymentSettled`)
    *   `amount_fiat` (NUMERIC, fiat value at time of invoice creation, from `InvoiceCreated` or `InvoiceSettled` metadata)
    *   `currency_fiat` (TEXT, e.g., "USD", "EUR", from `InvoiceCreated` or `InvoiceSettled` metadata)
    *   `payment_method` (TEXT, e.g., "BTC-OnChain", "BTC-Lightning", populated from `InvoicePaymentSettled`)
    *   `created_at_webhook_timestamp` (TIMESTAMPTZ, from `InvoiceCreated` webhook `timestamp`)
    *   `payment_settled_at_webhook_timestamp` (TIMESTAMPTZ, nullable, from `InvoicePaymentSettled` webhook `timestamp`)
    *   `final_settled_at_webhook_timestamp` (TIMESTAMPTZ, nullable, from `InvoiceSettled` webhook `timestamp`)
    *   `received_at` (TIMESTAMPTZ, when the *first relevant* webhook for this invoice was received by our API and an initial record was created or identified)
    *   `raw_payload_created` (JSONB, nullable, to store the full `InvoiceCreated` webhook JSON string)
    *   `raw_payload_payment_settled` (JSONB, nullable, to store the full `InvoicePaymentSettled` webhook JSON string)
    *   `raw_payload_settled` (JSONB, nullable, to store the full `InvoiceSettled` webhook JSON string)
    *   `inserted_at` (TIMESTAMPTZ, Ecto managed)
    *   `updated_at` (TIMESTAMPTZ, Ecto managed)
*   **F2.3**: API shall parse incoming webhook payloads (`InvoiceCreated`, `InvoicePaymentSettled`, `InvoiceSettled`) and map relevant fields to the `transactions` table. The record for a given `btcpay_invoice_id` will be created or updated incrementally as webhooks arrive. The `store_id` will be populated from the `InvoiceCreated` event.
*   **F2.4**: API shall write successfully validated and parsed transaction data (or updates) to the Primary PostgreSQL database.
*   **F2.5**: The system should handle potential duplicate webhooks gracefully (e.g., by using `btcpay_invoice_id` as a unique constraint for creation and idempotently processing updates).

### F3: Database Replication
*   **F3.1**: A PostgreSQL read replica shall be configured.
*   **F3.2**: Replication from the primary to the read replica should be streaming/asynchronous.
*   **F3.3**: The Dashboard Service shall be configured to read data exclusively from the read replica.

### F4: Real-time Dashboard
*   **F4.1**: Dashboard shall display the following metrics, updated in real-time:
    *   Total number of transactions.
    *   Total number of participating stores (distinct `store_id`).
    *   Total value received (sum of `amount_fiat`, and potentially `amount_crypto` separately).
    *   Average transaction amount (fiat).
    *   Percentage breakdown by `payment_method`.
    *   (Optional) A list/feed of recent transactions.
    *   Countdown to the end of the record attempt (start/end times configured via environment variables).
*   **F4.2**: Dashboard shall query the Dashboard Service (which reads from the Read Replica DB) to fetch data.
*   **F4.3**: Real-time updates can be achieved using Phoenix LiveView, Phoenix Channels with WebSockets, or efficient client-side polling.

### F5: Docker Compose Setup
*   **F5.1**: A `docker-compose.yml` file shall define and configure services for:
    *   The Elixir/Phoenix Application.
    *   PostgreSQL Primary Database.
    *   PostgreSQL Read Replica Database.
*   **F5.2**: Docker configurations should include:
    *   Persistent volumes for database data.
    *   Network configuration for inter-service communication.
    *   Environment variable management for secrets and configurations (e.g., database credentials, BTCPayServer webhook secret).
    *   Initial database schema migration setup.
    *   PostgreSQL replication configuration.

## 4. Development Phases & Steps

### Phase 1: Core API & Database Setup (Elixir & PostgreSQL) - Docker First Approach

1.  **Step 1.1: Initial Docker Environment Setup**
    *   Create a `Dockerfile` for the Elixir/Phoenix application. This initial Dockerfile should be suitable for development (e.g., allowing code mounting, running `mix` commands) and will later be adapted/extended for production releases (multi-stage build).
    *   Create `docker-compose.yml` at the project root.
    *   Define services within `docker-compose.yml`:
        *   `app`: The Elixir/Phoenix application service, built from the `Dockerfile`. Configure it for development with volume mounts for live code reloading.
        *   `postgres_primary`: The PostgreSQL Primary Database service (e.g., `image: postgres:15`).
        *   `postgres_replica`: The PostgreSQL Read Replica Database service (e.g., `image: postgres:15`).
    *   Configure basic environment variables (placeholders initially, to be refined) for database connections, application port, etc., within `docker-compose.yml` or an `.env` file.
    *   Set up named volumes for PostgreSQL data persistence (`pgdata_primary`, `pgdata_replica`).
    *   Establish basic network configuration in `docker-compose.yml` to allow services to communicate.
    *   *Goal*: Be able to run `docker-compose up -d postgres_primary` and have a PostgreSQL instance running.
    *   *Status (Step 1.1)*:
        *   `Dockerfile` created (version: `elixir:1.16.3-otp-26`) for the Elixir application base environment.
        *   `docker-compose.yml` created, defining `app`, `postgres_primary` (image: `postgres:15`), and `postgres_replica` (image: `postgres:15`) services.
        *   Environment variables in `docker-compose.yml` use defaults (e.g., `\${PRIMARY_DB_USER:-postgres}`) and can be overridden (e.g., via an `.env` file).
        *   Named volumes `pgdata_primary` and `pgdata_replica` configured for PostgreSQL data persistence.
        *   Basic networking is handled by Docker Compose default network; services are on the same network and can communicate via service names.
        *   The goal of running `docker-compose up -d postgres_primary` should now be achievable to start the primary database.

2.  **Step 1.2: Initialize Elixir Project (Phoenix) *within Docker***
    *   Once the `app` service is defined in `docker-compose.yml` (even without a fully built Elixir app inside yet, it can use a base Elixir image for this step), run the Phoenix project generator *inside* the Docker container, ensuring files are created in the mounted local directory.
        Command: `docker-compose run --rm app mix phx.new . --app btcpay_tracker --database postgres --live --no-dashboard --no-mailer` (The `.` indicates current directory, assuming project root is mounted).
    *   Adjust the generated Phoenix project's configuration (`config/dev.exs`, `config/test.exs`) to use environment variables for database hostnames (e.g., `postgres_primary`, `postgres_replica`), ports, and credentials provided by Docker Compose.
    *   Ensure the application's `Dockerfile` is adjusted if necessary after project generation (e.g., `COPY . .`, `mix deps.get`).
    *   *Goal*: Have a runnable Phoenix application skeleton, configured for the Docker environment. `docker-compose up app` should start the Phoenix server.
    *   *Status (Step 1.2)*:
        *   Phoenix project `btcpay_tracker` generated in the project root using `docker-compose run --build --rm app mix phx.new . --app btcpay_tracker --database postgres --live --no-dashboard --no-mailer`. User confirmed 'Yes' to dependency installation.
        *   `config/dev.exs` and `config/test.exs` updated to use environment variables (`DATABASE_HOST`, `DATABASE_USER`, `DATABASE_PASSWORD`, `DATABASE_NAME`, `SECRET_KEY_BASE`) for database and secret key configuration, with fallbacks for local setup.
        *   `docker-compose.yml` updated for the `app` service to include `command: sh -c "mix ecto.setup && mix phx.server"` to run database setup tasks and start the Phoenix server on `docker-compose up app`.
        *   Current `Dockerfile` (from Step 1.1, including `phx_new` installation) remains suitable for development with volume mounts; `mix deps.get` was handled during project generation. Further `Dockerfile` refinement (e.g. for production builds with `COPY . .`) is deferred as per PRD.
        *   The goal of having a runnable Phoenix skeleton configured for Docker should now be met. Running `docker-compose up app` should attempt to start the server. (Database migration is the next step).

3.  **Step 1.3: Define Database Schema (Ecto) & Initial Migration (within Docker)**
    *   Create an Ecto schema module (e.g., `BtcpayTracker.Transactions.Transaction`) for the `transactions` table based on F2.2.
    *   Generate the migration file using a Docker Compose command: `docker-compose run --rm app mix ecto.gen.migration create_transactions_table`.
    *   Implement the migration in the generated file to create the `transactions` table with appropriate columns, types, and constraints (e.g., unique constraint on `btcpay_invoice_id`).
    *   Run the initial database migrations: `docker-compose run --rm app mix ecto.migrate`.
    *   *Goal*: The `transactions` table exists in the `postgres_primary` database.
    *   *Status (Step 1.3)*:
        *   Ecto schema `BtcpayTracker.Transactions.Transaction` created in `lib/btcpay_tracker/transactions/transaction.ex` as per F2.2, using `:binary_id` for PK and `:map` for `raw_payload` (JSONB).
        *   Migration file `priv/repo/migrations/20250515023835_create_transactions_table.exs` generated using `docker-compose run --rm app mix ecto.gen.migration create_transactions_table`.
        *   Migration implemented to create the `transactions` table with specified columns (including `id :binary_id, primary_key: true`), types, null constraints, and a unique index on `btcpay_invoice_id`.
        *   Ran `docker-compose run --rm app mix ecto.create` (confirmed database already existed).
        *   Ran `docker-compose run --rm app mix ecto.migrate` successfully. The `transactions` table is now created in the `postgres_primary` database.
        *   (Addressed intermediate issues: fixed duplicated config files, ran `mix deps.get`, resolved database disk space and recovery issues.)
        *   **A second migration `update_transactions_for_multi_webhooks` (e.g., `priv/repo/migrations/20250515141930_update_transactions_for_multi_webhooks.exs`) was created and run to:**
            *   Modify the `status` field default to "pending".
            *   Add `created_at_webhook_timestamp` (TIMESTAMPTZ).
            *   Add `payment_settled_at_webhook_timestamp` (TIMESTAMPTZ, nullable).
            *   Add `final_settled_at_webhook_timestamp` (TIMESTAMPTZ, nullable).
            *   Add `raw_payload_created` (JSONB).
            *   Add `raw_payload_payment_settled` (JSONB, nullable).
            *   Add `raw_payload_settled` (JSONB, nullable).
            *   Remove the old `settled_at` and `raw_payload` fields.
        *   The `BtcpayTracker.Transactions.Transaction` Ecto schema was updated to reflect these changes, including new fields and an `update_changeset/2` function.
        *   **A third migration `add_store_id_to_transactions` (e.g., `priv/repo/migrations/20250515145713_add_store_id_to_transactions.exs`) was created and run to:**
            *   Add a `store_id` (TEXT, nullable) column to the `transactions` table.
            *   Create an index on the `store_id` column.
        *   The `BtcpayTracker.Transactions.Transaction` Ecto schema was updated to include the `store_id` field.

4.  **Step 1.4: Configure PostgreSQL Replication (in Docker Compose)**
    *   Update `docker-compose.yml` and create necessary PostgreSQL configuration files (e.g., `primary.conf`, `replica.conf`, `recovery.conf` or using environment variables for PG 12+) to set up streaming replication from `postgres_primary` to `postgres_replica`.
        *   Primary: Configure `postgresql.conf` for `wal_level = replica`, `max_wal_senders`, `archive_mode` (optional but good for Point-in-Time Recovery), `archive_command`. Update `pg_hba.conf` to allow replication connections from the replica.
        *   Replica: Configure to be a hot standby. Use `primary_conninfo` (in `postgresql.auto.conf` or passed as env var) to specify the primary's connection details. Use a `standby.signal` or `recovery.signal` file.
    *   Verify replication is working by inserting data into the primary and checking if it appears in the replica.
    *   *Goal*: Data written to `postgres_primary` is automatically replicated to `postgres_replica`.
    *   *Status (Step 1.4)*: **Successfully Implemented.** Streaming replication from `postgres_primary` to `postgres_replica` is now configured and working.
        *   Custom `postgresql.conf` and `pg_hba.conf` files are mounted into the `postgres_primary` container to enable replication features (`wal_level = replica`, `max_wal_senders`, etc.) and allow connections from the replica user.
        *   The `postgres_replica` service in `docker-compose.yml` uses a custom command that:
            1.  Ensures correct ownership and permissions of its data directory (`/var/lib/postgresql/data`).
            2.  Waits for the primary database to be available.
            3.  Uses `gosu postgres pg_basebackup ... -R -S replication_slot_slave1` to perform a base backup from the primary, automatically creating `standby.signal` and populating `postgresql.auto.conf` for recovery. The replication slot `replication_slot_slave1` must be created on the primary beforehand.
            4.  Starts the PostgreSQL server using `gosu postgres postgres ...`, which then enters standby mode and begins streaming WALs from the primary.
        *   The setup required careful sequencing of `docker-compose` commands: starting the primary first, then creating the replication user and slot on the primary via SQL, and finally starting the replica.
        *   Issues related to Docker volume permissions, `pg_basebackup` execution context, and PostgreSQL server startup permissions within the replica container were resolved by running relevant commands (like `chown`, `pg_isready`, `pg_basebackup`, and `postgres` itself) as the `postgres` user via `gosu`.
        *   Verification was performed by creating data on the primary, observing it on the replica, and confirming that write operations fail on the read-only replica.

5.  **Step 1.5: Webhook Endpoint Implementation (Basic - Develop within Docker)**
    *   Create a Phoenix controller (e.g., `WebhookController`) and a route for the webhook endpoint (F1.1, e.g., `POST /api/webhooks/btcpay/invoice_settled`).
    *   Initially, the endpoint should log the incoming request body and headers and return a `200 OK` response.
    *   Development occurs locally, with changes reflected in the running Docker container via volume mounts. Test by sending sample POST requests to the endpoint exposed by Docker.
    *   *Goal*: A functional webhook endpoint that can receive and log data.
    *   *Status (Step 1.5)*:
        *   `BtcpayTrackerWeb.WebhookController` created with an `invoice_settled/2` action. (This action was later refactored).
        *   Route `POST /api/webhooks/btcpay/invoice_settled` added to `lib/btcpay_tracker_web/router.ex`. (This route was later changed).
        *   The endpoint initially logged request headers and body and returns a `200 OK`.
        *   **Updated:** The route has been changed to `POST /api/webhooks/btcpay/events` in `lib/btcpay_tracker_web/router.ex`.
        *   **Updated:** The `WebhookController` now has a single `handle_event/2` action that inspects the payload type to delegate processing.

6.  **Step 1.6: Webhook Signature Validation (Develop within Docker)**
    *   Implement logic in the `WebhookController` (or a plug) to verify the `BTCPAY-SIG` header using HMAC-SHA256 and a configurable secret (F1.2). The secret should be loaded from an environment variable.
    *   Reject requests with invalid or missing signatures with an appropriate HTTP status code (e.g., `401 Unauthorized` or `403 Forbidden`).
    *   *Goal*: Only authenticated webhooks from BTCPayServer are processed further.
    *   *Status (Step 1.6)*:
        *   Created `BtcpayTrackerWeb.Plugs.CacheBodyReader` to cache the raw request body.
        *   Configured `Plug.Parsers` in `lib/btcpay_tracker_web/endpoint.ex` to use `CacheBodyReader`.
        *   Updated `BtcpayTrackerWeb.WebhookController` to:
            *   Retrieve `BTCPAY_WEBHOOK_SECRET` from environment variables.
            *   Extract and validate the `BTCPAY-SIG` (format `sha256=HEX_HASH`) header.
            *   Calculate HMAC-SHA256 of the raw body using the secret.
            *   Perform secure comparison of the calculated hash with the provided hash.
            *   Returns `200 OK` on success, or `400`, `401`, `403`, `500` on various error conditions (missing secret, missing/invalid header, validation failure).
        *   Addressed compiler warnings (deprecated `Logger.warn`, unused `params`, `crypto:mac` vs `:crypto.mac`, removed Swoosh mailer).

7.  **Step 1.7: Webhook Payload Parsing & Data Persistence (Develop within Docker)**
    *   Define Elixir structs (e.g., `BtcpayTracker.Webhooks.InvoiceCreatedPayload`, `BtcpayTracker.Webhooks.InvoicePaymentSettledPayload`, `BtcpayTracker.Webhooks.InvoiceSettledPayload`) to represent the expected payloads.
    *   Implement JSON parsing logic for each relevant webhook payload, populating the respective structs.
    *   Map the parsed fields to the `BtcpayTracker.Transactions.Transaction` Ecto schema. This will involve:
        *   On `InvoiceCreated`: Creating a new transaction record with status "pending" and initial data.
        *   On `InvoicePaymentSettled`: Finding the existing record by `btcpay_invoice_id` and updating it with crypto amount, currency, payment method, and payment settlement timestamp.
        *   On `InvoiceSettled`: Finding the existing record and updating its status to "settled" and recording the final settlement timestamp.
    *   Save changes to the primary database using Ecto.
    *   Handle potential errors gracefully (e.g., database errors, validation errors, trying to update a non-existent record if `InvoiceCreated` was missed, duplicate `btcpay_invoice_id` on creation).
    *   *Goal*: Validated and parsed webhook data from `InvoiceCreated`, `InvoicePaymentSettled`, and `InvoiceSettled` events is successfully stored and updated in the `postgres_primary` database.
    *   *Status (Step 1.7)*:
        *   (Previous status for single `InvoiceSettled` webhook handling is superseded by the multi-webhook strategy).
        *   **Updated for multi-webhook strategy implementation**:
        *   The system has been refactored to handle `InvoiceCreated`, `InvoicePaymentSettled`, and `InvoiceSettled` webhooks as per the PRD.
        *   **Payload Structs Created/Updated:**
            *   `BtcpayTracker.Webhooks.InvoiceCreatedPayload` created in `lib/btcpay_tracker/webhooks/invoice_created_payload.ex`.
            *   `BtcpayTracker.Webhooks.InvoicePaymentSettledPayload` created in `lib/btcpay_tracker/webhooks/invoice_payment_settled_payload.ex`.
            *   `BtcpayTracker.Webhooks.InvoiceSettledPayload` in `lib/btcpay_tracker/webhooks/invoice_settled_payload.ex` was refined.
        *   **Ingestion Logic (`BtcpayTracker.Ingestion` module in `lib/btcpay_tracker/ingestion.ex`):**
            *   A general `process_event/3` function was introduced, which receives the event type (string), the decoded JSON map, and the raw JSON body string. It dispatches to specific private functions based on the event type.
            *   `process_invoice_created/2`:
                *   Parses the payload using `InvoiceCreatedPayload.changeset/1`.
                *   Extracts initial data: `btcpay_invoice_id`, `btcpay_order_id` (from metadata), fiat amount/currency (from metadata using `parse_fiat_string/1`), `created_at_webhook_timestamp` (from payload's `timestamp`).
                *   Sets `status` to "pending" and `received_at` to current UTC.
                *   Populates the `store_id` field from the `storeId` in the `InvoiceCreated` payload.
                *   Stores the raw JSON body in `raw_payload_created`.
                *   Inserts a new `Transaction` record using `Transaction.changeset/2` with `on_conflict: :nothing` for `btcpay_invoice_id`. Gracefully handles duplicates by logging and returning the existing transaction.
            *   `process_invoice_payment_settled/2`:
                *   Parses using `InvoicePaymentSettledPayload.changeset/1`.
                *   Retrieves the existing `Transaction` by `btcpay_invoice_id`.
                *   Updates: `amount_crypto` (from `payment.value` via `cast_to_decimal/1`), `currency_crypto` (derived from `paymentMethod` using `extract_crypto_currency/1`), `payment_method`, `payment_settled_at_webhook_timestamp` (from payload's `timestamp`).
                *   Sets `status` to "processing_payment".
                *   Stores the raw JSON body in `raw_payload_payment_settled`.
                *   Uses `Transaction.update_changeset/2` and `Repo.update/1`. Handles cases where the initial transaction record might be missing.
            *   `process_invoice_final_settled/2` (renamed from the old `process_invoice_settled`):
                *   Parses using `InvoiceSettledPayload.changeset/1`.
                *   Retrieves the existing `Transaction` by `btcpay_invoice_id`.
                *   Updates: `status` to "settled", `final_settled_at_webhook_timestamp` (from payload's `timestamp`).
                *   Stores the raw JSON body in `raw_payload_settled`.
                *   If fiat details (`amount_fiat`, `currency_fiat`) were initially nil, it attempts to populate them from this payload's metadata.
                *   Uses `Transaction.update_changeset/2` and `Repo.update/1`.
                *   Includes fallback logic: If an `InvoiceSettled` event arrives for an unknown `btcpay_invoice_id` (i.e., `InvoiceCreated` was missed), it creates a new transaction record with status "settled" and populates fields from the current payload. `raw_payload_created` is set to a special map indicating it was auto-generated.
        *   **Helper functions in Ingestion module**:
            *   `parse_fiat_string/1` and `cast_to_decimal/1` are maintained and slightly improved for robustness.
            *   `extract_crypto_currency/1` was added to derive crypto currency from the `paymentMethod` string.
        *   **Webhook Controller (`BtcpayTrackerWeb.WebhookController`):**
            *   The `handle_event/2` action now decodes the JSON to get the `type` field.
            *   It then calls `BtcpayTracker.Ingestion.process_event/3` asynchronously, passing the event type string, the full decoded JSON map, and the original raw JSON body.
        *   **Database Schema (`BtcpayTracker.Transactions.Transaction`):**
            *   Updated to include `created_at_webhook_timestamp`, `payment_settled_at_webhook_timestamp`, `final_settled_at_webhook_timestamp`.
            *   The single `raw_payload` field was replaced with `raw_payload_created`, `raw_payload_payment_settled`, and `raw_payload_settled` (all type `:map`, storing JSONB).
            *   The `status` field default is now "pending".
            *   The `store_id` field was added.
            *   The old `settled_at` field was removed.
            *   An `update_changeset/2` function was added for processing updates from subsequent webhooks.
        *   The implementation successfully stores and updates transaction data based on the sequence of webhooks.
        *   **Further Debugging & Refinements (Post-Initial Implementation):**
            *   Resolved an Ecto casting error for `raw_payload_created` (and other raw payload fields) by ensuring the decoded JSON map (Elixir map) from `BtcpayTracker.Ingestion.process_event/3` was passed to the Ecto changeset for these `:map` type fields, instead of the raw JSON string. This involved changing `raw_payload_created: raw_body` to `raw_payload_created: decoded_json_map` (and similarly for other payload fields) in the `BtcpayTracker.Ingestion` module.
            *   Addressed a `Postgrex.Error` (not_null_violation on `amount_crypto`). The `amount_crypto` and `currency_crypto` fields in the `transactions` table were initially created with `null: false` constraints. However, these fields are only populated upon receiving the `InvoicePaymentSettled` webhook. A new migration (`make_crypto_fields_nullable_in_transactions`) was generated and applied to alter these columns to `null: true`, resolving the insertion error for `InvoiceCreated` events.
            *   Cleaned up compiler warnings in `BtcpayTracker.Ingestion` related to unused `_raw_body` parameters in the specific event processing functions (`process_invoice_created`, `process_invoice_payment_settled`, `process_invoice_final_settled`) by refactoring them to only accept `decoded_json_map` and updating the main `process_event/3` dispatcher accordingly.

### Phase 2: Dashboard Implementation (Phoenix LiveView/API)

1.  **Step 2.1: Dashboard Service Setup**
    *   If using Phoenix LiveView, create LiveView modules for the dashboard.
    *   If using a separate frontend, create Phoenix controller actions to expose data via a JSON API.
    *   Configure Ecto Repo for the read replica and ensure the Dashboard Service uses it for all reads.
    *   *Goal*: A basic LiveView or API endpoint setup for the dashboard, capable of serving data.
    *   *Status (Step 2.1)*:
        *   Phoenix LiveView module `BtcpayTrackerWeb.DashboardLive` created in `lib/btcpay_tracker_web/live/dashboard_live.ex`.
        *   Route `live "/dashboard", DashboardLive` added to `lib/btcpay_tracker_web/router.ex`.
        *   **The Dashboard Service is now configured to read data from the Read Replica DB (F3.3).**
            *   A new Ecto repo, `BtcpayTracker.Repo.Replica`, was created and configured to connect to the `postgres_replica` service. It's marked as `read_only: true` and configured with `migrations_paths: []` and `priv: false` to prevent it from participating in migration tasks.
            *   The `BtcpayTracker.Repo.Replica` is included in the application's supervision tree.
            *   The `BtcpayTracker.Dashboard` context module functions were updated to accept an optional `repo` argument, defaulting to the primary `BtcpayTracker.Repo`.
            *   The `BtcpayTracker.Dashboard.MetricsAggregator`, which provides data to `DashboardLive`, has been updated to call `BtcpayTracker.Dashboard` functions using `BtcpayTracker.Repo.Replica`.
            *   Mix task aliases for Ecto (e.g., `ecto.setup`, `ecto.reset`, `test`) in `mix.exs` were updated to explicitly target `BtcpayTracker.Repo` (the primary) for schema-modifying operations.
        *   The goal is met for a LiveView setup, and it now queries the read replica for dashboard data.

2.  **Step 2.2: Implement Dashboard Queries**
    *   Write Ecto queries to fetch data for the dashboard metrics (F4.1) from the read replica.
    *   Examples:
        *   `SELECT COUNT(*) FROM transactions;`
        *   `SELECT SUM(amount_fiat), currency_fiat FROM transactions GROUP BY currency_fiat;`
        *   `SELECT AVG(amount_fiat) FROM transactions WHERE currency_fiat = 'TARGET_FIAT';`
        *   `SELECT payment_method, COUNT(*) as count FROM transactions GROUP BY payment_method;`
    *   *Goal*: Ecto functions exist to retrieve all necessary data points for the dashboard.
    *   *Status (Step 2.2)*:
        *   `BtcpayTracker.Dashboard` context module created in `lib/btcpay_tracker/dashboard.ex`.
        *   Functions implemented for:
            *   `count_total_transactions/0`
            *   `sum_total_value_fiat/0` (grouped by currency)
            *   `avg_transaction_value_fiat/0` (grouped by currency)
            *   `get_payment_method_breakdown/0`
            *   `list_recent_transactions/1`
            *   `sum_total_value_crypto/0` (grouped by currency, for BTC totals)
            *   `avg_transaction_value_crypto/0` (grouped by currency, for BTC averages)
            *   `count_distinct_store_ids/0` (for participating stores count)
        *   `BtcpayTrackerWeb.DashboardLive` module's `load_dashboard_data/1` function uses these queries to populate assigns.
        *   Metrics from F4.1 (total transactions, total value, average transaction, payment method breakdown, recent transactions) are covered.
        *   **New metric:** Participating Stores count added.
        *   Currently, queries fetch all transaction data. TODOs are in place in `BtcpayTracker.Dashboard` to refine queries to filter by `status = "settled"` when appropriate for dashboard display.
        *   The goal is met.

3.  **Step 2.3: Design Dashboard UI (Phoenix LiveView or Frontend HTML/JS)**
    *   Create the HTML structure for the dashboard.
    *   Display the metrics fetched in Step 2.2.
    *   *Goal*: A viewable dashboard page displaying the key metrics.
    *   *Status (Step 2.3)*:
        *   The `render/1` function in `BtcpayTrackerWeb.DashboardLive` provides a basic HTML structure using Tailwind CSS classes.
        *   It displays: total transactions, total value (primary fiat), average transaction value (primary fiat), payment method breakdown, and a table of recent transactions.
        *   The UI is functional for displaying core metrics. Further detailed UI/UX enhancements are out of scope for the initial MVP unless specified otherwise.
        *   **Updated:** Added display for Total Value (BTC) and Average Transaction (BTC). All currency values (fiat and crypto) are now robustly formatted to the correct number of decimal places (e.g., 2 for primary fiat, 8 for BTC) and avoid scientific notation, using the `format_decimal/2` helper in `BtcpayTrackerWeb.DashboardLive` which leverages `Decimal` library functions. Display layout adjusted for the new metrics (2 columns on medium screens and up).
        *   **New metric displayed:** "Participating Stores" count.
        *   The goal is met.

4.  **Step 2.4: Implement Real-time Updates**
    *   **Using Phoenix LiveView**: Leverage LiveView's capabilities to automatically update the UI when underlying data changes (e.g., via `Phoenix.PubSub` after a new transaction is saved).
    *   **Using Phoenix Channels**: After a transaction is saved, publish an event. The frontend client (connected via WebSocket) receives the event and updates the UI or re-fetches data.
    *   **Using Polling (Less Ideal)**: Frontend polls API endpoints at regular intervals.
    *   *Goal*: Dashboard metrics update automatically when new, relevant data is ingested.
    *   *Status (Step 2.4)*:
        *   `BtcpayTrackerWeb.DashboardLive` subscribes to the `"transactions"` Phoenix PubSub topic in `mount/3`.
        *   `handle_info/2` callbacks for `:new_transaction_event` and `:updated_transaction_event` are implemented in `DashboardLive`, which call `load_dashboard_data/1` to refresh assigns.
        *   `BtcpayTracker.Ingestion` module now broadcasts `:new_transaction_event` and `:updated_transaction_event` on the `"transactions"` topic after successful database operations.
        *   The real-time update mechanism via Phoenix LiveView and PubSub is implemented.
        *   The goal is met.

### Phase 3: BTCPayServer Integration & Testing

1.  **Step 3.1: Configure BTCPayServer Webhook**
    *   In your BTCPayServer store settings, add a new webhook.
    *   Set the "Payload URL" to your API's webhook endpoint (e.g., `https://yourdomain.com/api/webhooks/btcpay/invoice_settled`).
    *   A "Secret" will be generated by BTCPayServer. Copy this secret and configure it in your Elixir application (e.g., via an environment variable).
    *   Ensure the webhook is configured to send the `InvoiceSettled` event (or relevant event that signifies full payment).
2.  **Step 3.2: End-to-End Testing**
    *   Create and pay invoices in BTCPayServer.
    *   Verify webhooks are received by the API.
    *   Check for signature validation success/failure logs.
    *   Confirm transaction data is correctly stored in the primary database.
    *   Verify data is replicated to the read replica.
    *   Observe the dashboard updating in real-time with the new transaction data.
    *   Test edge cases (e.g., network delays, BTCPayServer resending webhooks).
3.  **Step 3.3: Data Verification**
    *   Cross-reference data in the database and on the dashboard with the `project-overview.txt` requirements (date/time, amounts, payment method, ID).
    *   Ensure correct mapping of "payment method" from BTCPayServer data (this might require inspecting sample webhook payloads to determine how on-chain, Lightning, NFC, QR, etc., are represented).

### Phase 4: Refinements & Deployment Preparation

1.  **Step 4.1: Comprehensive Error Handling & Logging**
    *   Implement robust error handling for API requests, database operations, and webhook processing.
    *   Add structured logging throughout the application for easier debugging and monitoring.
    *   *Status (Step 4.1)*: **Good progress made.**
        *   Added `try/rescue` blocks to critical functions in the `BtcpayTracker.Ingestion` module to catch and log unexpected errors with stacktraces.
        *   Identified and resolved an issue where `MIX_ENV` was defaulting to `:dev` instead of `:test` for supervised processes (like `MetricsAggregator`) during `docker-compose run ... mix test`. Corrected by ensuring `MIX_ENV=test` is set for the test execution environment, allowing conditional logic (e.g., for logging, or test-specific behavior like `MetricsAggregator` not loading data from DB on init) to function as expected. This was crucial for unblocking Ecto Sandbox initialization.
        *   Reviewed existing logging in `WebhookController` and `Ingestion` modules; they provide good contextual information for successes and various failure modes.

2.  **Step 4.2: Unit and Integration Tests**
    *   Write unit tests for critical components (webhook validation, data parsing, Ecto interactions).
    *   Write integration tests for the webhook flow and dashboard data retrieval.
    *   *Status (Step 4.2)*: **Partially Addressed. Initial unit tests created.**
        *   Successfully resolved complex Ecto Sandbox setup issues that were preventing tests from running correctly. This involved:
            *   Configuring both `BtcpayTracker.Repo` and `BtcpayTracker.Repo.Replica` for `pool: Ecto.Adapters.SQL.Sandbox` in `config/test.exs`.
            *   Ensuring `Ecto.Adapters.SQL.Sandbox.mode(..., :manual)` is set for both repos in `test_helper.exs`.
            *   Updating `BtcpayTracker.DataCase` to manage sandbox ownership for both repos.
            *   Modifying `BtcpayTracker.Dashboard.MetricsAggregator` to not load data from the database during its `init/1` callback when `Mix.env() == :test`, preventing interference with sandbox setup.
        *   Helper functions for parsing (`parse_fiat_string`, `cast_to_decimal`, `extract_crypto_currency`) were refactored from private functions in `BtcpayTracker.Ingestion` into a new public module `BtcpayTracker.ParsingUtils`.
        *   Unit tests for all functions in `BtcpayTracker.ParsingUtils` have been created and are passing. This covers parsing of fiat strings, casting values to `Decimal`, and extracting crypto currency symbols.
        *   The immediate next steps are to write unit tests for `BtcpayTracker.Ingestion`'s main processing functions (requiring mocking of `Repo` calls), Ecto changesets in `BtcpayTracker.Transactions.Transaction`, and the `BtcpayTrackerWeb.WebhookController`'s signature validation and routing logic. Integration tests will follow.

3.  **Step 4.3: Database Query Optimization**
    *   Review and optimize database queries for performance, especially those used by the dashboard.
    *   Add necessary database indexes (e.g., on `settled_at`, `payment_method`, `btcpay_invoice_id`).
    *   *Status (Step 4.3)*: **Successfully Implemented.**
        *   Verified existing indexes on `btcpay_invoice_id` (unique), `store_id`, `status`, `payment_method`, `currency_fiat`, `currency_crypto`, and `final_settled_at_webhook_timestamp`. These were added in previous steps or migrations.
        *   A new database migration (`add_index_on_inserted_at_to_transactions`) was created and applied to add an index on the `inserted_at` column in the `transactions` table. This optimizes queries that sort by transaction insertion time, such as the "recent transactions" list on the dashboard.
        *   Dashboard queries in `BtcpayTracker.Dashboard` have been updated to filter results by `status = "settled"` (where appropriate, e.g., for financial aggregations and payment method breakdowns). This ensures metrics accurately reflect completed transactions and can improve query performance by reducing the dataset.
        *   Ensured that `mix ecto.migrate` commands are run targeting only the primary repository (e.g., `mix ecto.migrate -r BtcpayTracker.Repo`) to prevent errors with the read-only replica. This operational detail will be added to the project's `README.md`.

4.  **Step 4.4: Security Hardening**
    *   Ensure all secrets (DB passwords, webhook secret) are managed securely (e.g., environment variables, Docker secrets).
        *   *Status*: **Updated.** HTTPS termination will be handled externally by Cloudflare Tunnels. The internal Nginx service is now configured to listen on HTTP (port 80) and proxy requests to the Phoenix application. SSL certificates and related Nginx configuration for local HTTPS have been removed.
    *   Review application dependencies for vulnerabilities.
        *   *Status*: Pending.
    *   Apply standard web application security best practices (e.g., HTTPS for all communication).
        *   *Status*: **Updated.** HTTPS termination will be handled externally by Cloudflare Tunnels. The internal Nginx service is now configured to listen on HTTP (port 80) and proxy requests to the Phoenix application. SSL certificates and related Nginx configuration for local HTTPS have been removed.

5.  **Step 4.5: Finalize Docker Compose for Production**
    *   Optimize Docker images for size and security.
    *   Configure resource limits for containers if necessary.
    *   Ensure logging drivers are configured for production.

6.  **Step 4.6: Documentation**
    *   Add README with setup instructions, environment variable definitions, and deployment notes.

## 5. Non-Functional Requirements

*   **NFR1: Performance**:
    *   Webhook ingestion: Should process incoming webhooks within 500ms under normal load.
    *   Dashboard: Should load initial data within 2 seconds and update in near real-time (sub-second latency for updates after data ingestion).
*   **NFR2: Scalability**:
    *   The system should be able to handle at least 10 settled invoice webhooks per second.
    *   Database replication should keep up with the write load.
*   **NFR3: Reliability & Availability**:
    *   The API and Dashboard services should aim for 99.9% uptime.
    *   No loss of successfully acknowledged webhook data.
    *   Graceful handling of BTCPayServer webhook retries.
*   **NFR4: Security**:
    *   Webhook endpoint must be secured against unauthorized access (signature validation).
    *   Database credentials and other secrets must be stored securely.
    *   Communication between BTCPayServer and the API, and between the client and the dashboard, should be over HTTPS.
*   **NFR5: Maintainability**:
    *   Code should be well-documented and follow Elixir/Phoenix best practices.
    *   Configuration should be externalized (environment variables).
*   **NFR6: Data Integrity**:
    *   Transaction data must accurately reflect the information received from BTCPayServer.
    *   Mechanisms to prevent duplicate transaction entries (e.g., unique constraints).

## 6. Future Considerations (Out of Scope for Initial MVP)

*   Admin interface for viewing raw webhooks, failed transactions, and system health.
*   More advanced analytics and reporting features on the dashboard.
*   Support for other BTCPayServer webhook events (e.g., `InvoiceProcessing`, `InvoiceExpired`).
*   Alerting mechanism for system failures or high error rates.
*   Horizontal scaling of the Elixir application and potentially the read replica pool.
*   Implementation of the "Countdown to the end of the record attempt" on the dashboard (may require separate logic/state management).
*   User authentication for accessing the dashboard if it needs to be private.

## 7. Open Questions / Clarifications Needed

*   **OQ1**: What is the exact structure of the BTCPayServer `InvoiceSettled` webhook payload? Specifically, how are fields like "payment method (on-chain, NFC card, QR code)" represented or derived? (This will require inspecting a sample payload from a live or test BTCPayServer instance).
    *   *User Update*: Provided a partial snippet. Key fields identified: `type: "InvoiceSettled"`, `invoiceId`, `metadata.orderId`, `timestamp` (for `final_settled_at_webhook_timestamp`).
    *   *Further Update*: Example payloads for `InvoiceCreated` and `InvoicePaymentSettled` were also provided and used to define their respective Ecto embedded schemas. The `paymentMethod` field from `InvoicePaymentSettled` (e.g., "BTC-LightningNetwork", "BTC") and the `payment.value` field are now used to derive `currency_crypto`, `amount_crypto`, and `payment_method` for the transaction record. Fiat amounts are primarily taken from `InvoiceCreated` metadata, with `InvoiceSettled` metadata as a fallback.