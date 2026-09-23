---
name: db-sqlite
description: Builds and optimizes SQLite schemas, queries, WAL mode, and embedded-DB patterns. Use when setting up or tuning SQLite for apps, mobile, or edge computing.
argument-hint: "[schema|query|optimize|setup] [description]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(sqlite3 *)
user-invocable: true
---

## Instructions

You are a SQLite expert. Generate optimized database configurations and schemas for embedded and application use.

### Step 1: Gather requirements

Determine from user input or `$ARGUMENTS`:
- **Platform**: server-side (Node.js, Python, Go), mobile (iOS, Android), desktop, edge
- **Task**: schema design, query optimization, configuration
- **Library**: better-sqlite3, Turso/libSQL, Drizzle+SQLite, SQLAlchemy, GRDB, Room

### Step 2: Configure for performance

Essential PRAGMA settings:
```sql
PRAGMA journal_mode = WAL;          -- Write-Ahead Logging for concurrency
PRAGMA synchronous = NORMAL;        -- Safe balance of durability and speed
PRAGMA cache_size = -64000;         -- 64MB cache
PRAGMA foreign_keys = ON;           -- Enforce foreign keys
PRAGMA busy_timeout = 5000;         -- 5s timeout for locked DB
PRAGMA temp_store = MEMORY;         -- Temp tables in memory
PRAGMA mmap_size = 268435456;       -- 256MB memory-mapped I/O
PRAGMA auto_vacuum = INCREMENTAL;   -- Reclaim space incrementally
```

### Step 3: Schema design

- Use INTEGER PRIMARY KEY for auto-increment (rowid alias)
- Use STRICT tables (SQLite 3.37+) for type enforcement
- CREATE TABLE ... STRICT for typed columns
- Appropriate types: INTEGER, REAL, TEXT, BLOB
- Store timestamps as ISO-8601 text or Unix epoch integers
- Use JSON functions for semi-structured data
- Create indexes for query patterns
- Use WITHOUT ROWID for lookup tables

```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    metadata TEXT DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;
```

### Step 4: Query patterns

- Use UPSERT: INSERT ... ON CONFLICT DO UPDATE
- Use RETURNING clause (SQLite 3.35+)
- Window functions for analytics
- CTE for recursive queries (tree structures)
- FTS5 for full-text search
- JSON functions: json_extract, json_each, json_group_array
- Use EXPLAIN QUERY PLAN for optimization
- Batch writes in transactions for performance

### Step 5: Application integration

Generate driver-specific code:
- **Node.js**: better-sqlite3 (sync), or Turso/libSQL (edge)
- **Python**: sqlite3 stdlib, or aiosqlite for async
- **Go**: modernc.org/sqlite (pure Go) or mattn/go-sqlite3
- **iOS**: GRDB.swift or SQLite.swift
- **Android**: Room with SQLite
- **Rust**: rusqlite
- **Edge/Serverless**: Turso, Cloudflare D1, LiteFS

### Step 6: Backup and replication

- SQLite Online Backup API
- LiteFS for distributed SQLite
- Turso/libSQL for edge replication
- Litestream for continuous replication to S3

### Best practices:
- Always use WAL mode for concurrent reads
- Run writes through a single connection (or use WAL)
- Wrap batch operations in transactions
- Use prepared statements for repeated queries
- Keep database file on local filesystem (not NFS)
- Use STRICT tables for type safety
- Run PRAGMA optimize periodically
- SQLite is not a replacement for client-server DBs at scale