- Improve tracing
- Transactions and savepoints:

  - `DB#transaction {}` - does a `BEGIN..COMMIT` - non-reentrant!
  - `DB#savepoint(name)` - creates a savepoint
  - `DB#release(name)` - releases a savepoint
  - `DB#rollback` - raises `Extralite::Rollback`, which is rescued by `DB#transaction`
  - `DB#rollback_to(name)` - rolls back to a savepoint

- More database methods:

  - `Database#quote`
  - `Database#busy_timeout=` https://sqlite.org/c3ref/busy_timeout.html
  - `Database#cache_flush` https://sqlite.org/c3ref/db_cacheflush.html
  - `Database#release_memory` https://sqlite.org/c3ref/db_release_memory.html

- Security

  - Enable extension loading by using
    [SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION](https://www.sqlite.org/c3ref/c_dbconfig_defensive.html#sqlitedbconfigenableloadextension)
    in order to prevent usage of `load_extension()` SQL function.
