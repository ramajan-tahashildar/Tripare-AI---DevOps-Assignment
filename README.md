# Hotel Booking Platform — DevOps Infrastructure

Production-grade AWS infrastructure with Terraform, local database reliability testing, and automated backup/restore workflows.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Repository Structure](#repository-structure)
3. [Prerequisites](#prerequisites)
4. [Part 1 & 2 — Terraform Infrastructure](#part-1--2--terraform-infrastructure)
5. [Part 3 — GitHub Actions CI](#part-3--github-actions-ci)
6. [Part 4 — Local Database Setup](#part-4--local-database-setup)
7. [Part 5 — Seed Data & Index Optimization](#part-5--seed-data--index-optimization)
8. [Part 6 — Backup & Restore](#part-6--backup--restore)
9. [Verification Steps](#verification-steps)
10. [Design Decisions](#design-decisions)

---

## Architecture Overview

```
Internet
    │
    ▼
┌─────────────────────────┐
│  Application Load       │  (public subnets, ports 80/443)
│  Balancer (ALB)         │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  ECS / Fargate          │  (private subnets, no public IPs)
│  (app containers)       │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  RDS PostgreSQL         │  (private subnets, no internet route)
│  (Multi-AZ in prod)     │
└─────────────────────────┘
```

**Security model:**
- ALB security group: accepts `0.0.0.0/0` on port 80/443 only
- ECS security group: accepts traffic from ALB security group only
- RDS security group: accepts port 5432 from ECS security group only
- RDS has `publicly_accessible = false` — unreachable from the internet

---

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── terraform.yml          # CI: fmt → init → validate → plan (PR comment)
├── infra/
│   ├── modules/
│   │   ├── network/               # VPC, subnets, IGW, NAT, security groups
│   │   ├── ecs/                   # ECS cluster, task definition, service, ALB
│   │   └── rds/                   # RDS PostgreSQL, parameter group, Secrets Manager
│   └── envs/
│       ├── dev/                   # Dev environment (small, no deletion protection)
│       └── prod/                  # Prod environment (HA, deletion protection on)
├── db/
│   ├── migrations/
│   │   ├── 001_create_hotel_bookings.sql
│   │   └── 002_create_booking_events.sql
│   ├── indexes/
│   │   └── 003_add_indexes.sql    # Optimised composite index + supporting indexes
│   └── seeds/
│       └── seed.sql               # 100+ bookings across 10 cities and 5 organisations
├── scripts/
│   ├── backup.sh                  # Timestamped pg_dump with auto-rotation
│   └── restore.sh                 # Restore into fresh DB + verification queries
├── docker-compose.yml             # Local PostgreSQL (auto-runs migrations + seed)
└── README.md
```

---

## Prerequisites

| Tool | Minimum version | Check |
|------|----------------|-------|
| Docker + Docker Compose | Docker 24+ | `docker --version` |
| Terraform | 1.6+ | `terraform -version` |
| PostgreSQL client (`psql`, `pg_dump`) | 15+ | `psql --version` |
| AWS CLI (optional — plan-only) | 2.x | `aws --version` |

---

## Part 1 & 2 — Terraform Infrastructure

### Module layout

```
infra/modules/network/    — VPC, public/private subnets, IGW, NAT, all security groups
infra/modules/ecs/        — ECS cluster + Fargate service + ALB + IAM execution role
infra/modules/rds/        — RDS PostgreSQL + subnet group + parameter group + Secrets Manager
```

### Environment differences

| Setting | `dev` | `prod` |
|---------|-------|--------|
| ECS CPU | 256 | 1024 |
| ECS Memory | 512 MiB | 2048 MiB |
| ECS replicas | 1 | 2 |
| RDS instance | `db.t3.micro` | `db.t3.medium` |
| RDS storage | 20 GiB (max 50) | 100 GiB (max 500) |
| Backup retention | 3 days | 30 days |
| Deletion protection | `false` | `true` |
| Multi-AZ | `false` | `true` |
| Final snapshot | skipped | taken |
| Backend S3 bucket | `my-terraform-state-dev` | `my-terraform-state-prod` |

### Validate Terraform (no AWS credentials needed)

```bash
# Dev environment
cd infra/envs/dev
terraform init -backend=false
terraform fmt -check -recursive ../../
terraform validate

# Prod environment
cd ../../prod
terraform init -backend=false
terraform validate
```

### Run a plan (requires AWS credentials)

```bash
cd infra/envs/dev

# Provide DB password via env var — never commit real secrets
export TF_VAR_rds_password="Dev\$ecurePass123!"

terraform init
terraform plan -refresh=false
```

### Backend state configuration

Each environment uses a separate S3 bucket and DynamoDB lock table:

```
dev  → s3://my-terraform-state-dev/hotel-booking/dev/terraform.tfstate
prod → s3://my-terraform-state-prod/hotel-booking/prod/terraform.tfstate
```

To bootstrap the S3 buckets before first `terraform init`, create them with versioning and server-side encryption enabled.

---

## Part 3 — GitHub Actions CI

The workflow file is at `.github/workflows/terraform.yml`.

**Triggers:** any Pull Request that touches `infra/**`

**Jobs:**

| Job | Steps | Notes |
|-----|-------|-------|
| `lint` | `terraform fmt -check -recursive infra/` | Posts result as PR comment |
| `plan (dev)` | init → validate → plan | Posts full plan as PR comment + uploads artifact |
| `plan (prod)` | init → validate → plan | Posts full plan as PR comment + uploads artifact |

The plan job overrides the S3 backend with a local backend for CI (no AWS state bucket required). AWS credentials are read from `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` repository secrets.

The plan output is posted as a PR comment via `actions/github-script` and also uploaded as a downloadable workflow artifact (7-day retention).

---

## Part 4 — Local Database Setup

### Start the database

```bash
docker compose up -d
```

This starts PostgreSQL 15 on `localhost:5432`. On first launch the container automatically runs, in order:

1. `001_create_hotel_bookings.sql` — creates the `hotel_bookings` table
2. `002_create_booking_events.sql` — creates the `booking_events` table with FK to bookings
3. `003_add_indexes.sql` — creates the optimised composite index and supporting indexes
4. `004_seed.sql` — inserts 100+ bookings and associated events

### Connection details

| Parameter | Value |
|-----------|-------|
| Host | `localhost` |
| Port | `5432` |
| Database | `hoteldb` |
| Username | `dbadmin` |
| Password | *(set in your `.env` file — see `.env.example`)* |

```bash
# Quick connectivity test
psql -h localhost -p 5432 -U dbadmin -d hoteldb -c "\dt"
```

### Optional pgAdmin UI

```bash
docker compose --profile tools up -d
# Open http://localhost:5050
# Email: set PGADMIN_DEFAULT_EMAIL in .env  /  Password: set PGADMIN_DEFAULT_PASSWORD in .env
# Add server: host=hotelapp_postgres, port=5432, user=dbadmin
```

### Stop / reset

```bash
docker compose down          # stop, keep data
docker compose down -v       # stop + wipe data (fresh re-seed on next up)
```

---

## Part 5 — Seed Data & Index Optimization

### Seed data summary

| Dimension | Values |
|-----------|--------|
| Total bookings | 100+ |
| Cities | delhi, mumbai, bangalore, hyderabad, chennai, kolkata, pune, jaipur, goa, ahmedabad, lucknow, surat |
| Organisations | 5 (`b1000000-…-0001` through `…-0005`) |
| Statuses | `PENDING`, `CONFIRMED`, `COMPLETED`, `CANCELLED`, `NO_SHOW` |
| Booking events | ~30 events covering created, confirmed, cancelled, completed, payment scenarios |
| Date range | Mix of recent (within 30 days) and older (45–90 days ago) rows |

### Target query being optimised

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city       = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

### Index strategy

**Primary index** (`003_add_indexes.sql`):

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_hotel_bookings_city_createdat
ON hotel_bookings (city, created_at)
INCLUDE (org_id, status, amount);
```

**Why this index?**

1. **Leading column `city` (equality filter)** — with many cities in the table, placing `city` first lets the index skip all non-Delhi rows at the B-tree root, narrowing the scan to a small fraction of the table.

2. **Second column `created_at` (range filter)** — because `city` is an equality predicate, PostgreSQL can treat the index as if it starts at `created_at` for that city slice. The B-tree range scan starts at `NOW() - 30 days` and stops at the end of the city block, skipping all older rows without reading them.

3. **`INCLUDE (org_id, status, amount)` (covering columns)** — `org_id` and `status` are in `GROUP BY`; `amount` is in `SUM()`. By including them in the index (not the key), PostgreSQL can satisfy the entire query with an **index-only scan** — it never touches the heap (table pages). This is the biggest performance win for an analytical aggregation query.

**Net effect:** `Seq Scan → Hash Aggregate` becomes `Index Only Scan → Hash Aggregate`, reducing I/O from O(n) to O(matching rows).

**Supporting indexes also created:**

| Index | Purpose |
|-------|---------|
| `idx_booking_events_booking_id` | Speeds up FK joins and `ON DELETE CASCADE` operations |
| `idx_hotel_bookings_pending` | Partial index — fast dashboard queries for pending bookings only |
| `idx_booking_events_payload_gin` | GIN index — enables fast JSONB key/value searches on `payload` |

### Verify index usage

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

Look for `Index Only Scan using idx_hotel_bookings_city_createdat` in the plan output.

---

## Part 6 — Backup & Restore

### Backup

```bash
./scripts/backup.sh
```

Creates a gzip-compressed, timestamped dump in `./backups/`:

```
backups/hoteldb_20240615_143022.sql.gz
```

The script:
- Waits for PostgreSQL to be ready (up to 30 s)
- Runs `pg_dump --format=plain` piped through `gzip`
- Validates the dump is non-empty
- Auto-rotates old backups (keeps last 7)
- Prints the exact path of the backup file

**Override defaults via environment variables:**

```bash
DB_NAME=mydb DB_USER=myuser DB_PASSWORD=mypass BACKUP_DIR=/tmp/bkp ./scripts/backup.sh
```

### Restore

```bash
# Restore the latest backup automatically
./scripts/restore.sh

# Restore a specific backup file
./scripts/restore.sh backups/hoteldb_20240615_143022.sql.gz
```

The script restores into a **separate database** (`hoteldb_restore` by default) so the live database is never touched. It then immediately runs verification queries.

**Override restore target:**

```bash
RESTORE_DB_NAME=hoteldb_test ./scripts/restore.sh
```

### Verifying the restore worked

The `restore.sh` script automatically prints three verification sections at the end:

**1. Row count check** — confirms data volume matches the source:

```
 table_name      | row_count
-----------------+-----------
 hotel_bookings  |       100
 booking_events  |        30
```

**2. Status distribution** — shows bookings grouped by status and total amount.

**3. Target query output** — runs the optimised analytical query against the restored database to confirm results match the original.

**4. Index presence** — lists all indexes in the restored database to confirm they were restored correctly.

**Manual verification (optional):**

```bash
# Compare row counts between live and restored databases
psql -h localhost -U dbadmin -d hoteldb         -c "SELECT COUNT(*) FROM hotel_bookings;"
psql -h localhost -U dbadmin -d hoteldb_restore  -c "SELECT COUNT(*) FROM hotel_bookings;"

# Check indexes exist in restored database
psql -h localhost -U dbadmin -d hoteldb_restore \
  -c "SELECT indexname FROM pg_indexes WHERE tablename = 'hotel_bookings';"
```

---

## Verification Steps (End-to-End)

### 1 — Terraform

```bash
cd infra/envs/dev
terraform init -backend=false
terraform fmt -check -recursive ../../
terraform validate
```

Expected: `Success! The configuration is valid.`

### 2 — Database

```bash
# Start
docker compose up -d

# Wait for healthy status
docker compose ps

# Verify tables and seed data
psql -h localhost -p 5432 -U dbadmin -d hoteldb \
  -c "SELECT COUNT(*) AS total_bookings FROM hotel_bookings;"

psql -h localhost -p 5432 -U dbadmin -d hoteldb \
  -c "SELECT city, COUNT(*) FROM hotel_bookings GROUP BY city ORDER BY city;"
```

### 3 — Backup

```bash
./scripts/backup.sh
ls -lh backups/
```

### 4 — Restore

```bash
./scripts/restore.sh
```

Review the printed verification output. All row counts should match the source database.

### 5 — Index verification

```bash
psql -h localhost -U dbadmin -d hoteldb -c "
EXPLAIN (ANALYZE, BUFFERS)
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
"
```

---

## Design Decisions

### Why a composite index on `(city, created_at) INCLUDE (org_id, status, amount)`?

See the [Index Strategy](#index-strategy) section above for the full explanation. The short answer: equality on `city` + range on `created_at` + covering columns for `GROUP BY` and `SUM` enables an index-only scan — the most efficient execution plan for this query.

### Why is RDS strictly private?

The RDS security group only allows inbound port 5432 from the ECS security group. There is no route from the internet to the private subnets, and `publicly_accessible = false`. Database access from a developer workstation must go through a bastion host or AWS SSM Session Manager port forwarding.

### Why separate S3 state buckets per environment?

Separate buckets provide hard isolation — a `terraform destroy` in dev cannot accidentally affect prod state. Each bucket also has its own DynamoDB lock table to prevent concurrent applies.

### Why `CONCURRENTLY` on index creation?

`CREATE INDEX CONCURRENTLY` builds the index without holding an `ACCESS EXCLUSIVE` lock, allowing reads and writes to continue during index creation. This is essential for production tables that cannot tolerate downtime.

### Why restore into a separate database?

Restoring into `hoteldb_restore` (not `hoteldb`) means the live database is never dropped during a restore test. This mirrors the real-world practice of restoring into a staging replica before cutting over.
