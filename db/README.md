# Database Schema Documentation

## Overview

This directory contains the SQLite database schema, migrations, and analytical queries for the expense tracker system.

## Directory Structure

```
db/
├── migrations/          # Database schema migrations
│   ├── 001_create_schema.sql
│   ├── 002_seed_initial_data.sql
│   └── 003_migrate_csv_data.py
├── queries/            # Sample analytical queries
│   ├── monthly_summary.sql
│   ├── yoy_comparison.sql
│   ├── top_merchants.sql
│   └── pivot_table.sql
└── README.md           # This file
```

## Schema Design

### Tables

1. **categories** - Expense categories with hierarchical structure
2. **financial_institutions** - Banks, cards, and payment services
3. **transactions** - Core transaction data with optimized indexing

### Key Features

- Year-based indexing for fast temporal queries
- Deduplication via UNIQUE constraints
- Support for installment payments
- Hierarchical category structure
- Comprehensive indexes for analytical queries

## Running Migrations

### Initial Setup

```bash
# Create database and run all migrations
python -m src.db.migrate
```

### Manual Migration

```bash
# Run specific migration
sqlite3 data/expense_tracker.db < db/migrations/001_create_schema.sql
```

## Data Migration from CSV

To migrate existing CSV data:

```bash
python db/migrations/003_migrate_csv_data.py
```

## Querying the Database

### CLI

```bash
# Open database in SQLite CLI
sqlite3 data/expense_tracker.db

# Run a query file
sqlite3 data/expense_tracker.db < db/queries/monthly_summary.sql
```

### Python

```python
import sqlite3

conn = sqlite3.connect('data/expense_tracker.db')
cursor = conn.cursor()

# Your queries here
cursor.execute("SELECT * FROM transactions LIMIT 10")
```

## Performance Optimization

### Maintenance Commands

```sql
-- Update statistics (run monthly)
ANALYZE;

-- Rebuild indexes (run annually)
REINDEX;

-- Reclaim space (run quarterly)
VACUUM;

-- Check integrity
PRAGMA integrity_check;
```

### Query Performance Tips

1. Always filter by `transaction_year` or `transaction_date`
2. Use indexed columns in WHERE clauses
3. Avoid `SELECT *` in production
4. Use `EXPLAIN QUERY PLAN` to verify index usage

## Capacity Planning

- Monthly transactions: ~500
- Annual transactions: ~6,000
- 5-year data: ~30,000 rows (~10MB)
- 10-year capacity: ~60,000 rows (~20MB)

SQLite can efficiently handle decades of personal expense data.

## Schema Validation

Run integrity checks after migrations:

```bash
python -m src.db.validate
```

## Backup Strategy

```bash
# Backup database
cp data/expense_tracker.db data/expense_tracker.db.backup

# Export to SQL
sqlite3 data/expense_tracker.db .dump > backup.sql

# Restore from SQL
sqlite3 data/expense_tracker_new.db < backup.sql
```

## Troubleshooting

### Database Locked Error

SQLite allows only one writer at a time. If you see "database is locked":

```python
# Increase timeout
conn = sqlite3.connect('data/expense_tracker.db', timeout=30.0)
```

### Slow Queries

1. Check if indexes are being used: `EXPLAIN QUERY PLAN SELECT ...`
2. Run `ANALYZE` to update statistics
3. Consider adding new indexes for your query patterns

### Constraint Violations

If duplicate transactions are rejected:

```python
# Use INSERT OR IGNORE to skip duplicates
cursor.execute("INSERT OR IGNORE INTO transactions (...) VALUES (...)")

# Or use INSERT OR REPLACE to update
cursor.execute("INSERT OR REPLACE INTO transactions (...) VALUES (...)")
```

## Further Reading

- [SQLite Documentation](https://www.sqlite.org/docs.html)
- [SQLite Query Optimizer](https://www.sqlite.org/optoverview.html)
- [SQLite Performance Tuning](https://www.sqlite.org/fasterthanfs.html)
