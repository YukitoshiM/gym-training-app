import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";

export function localD1Fixture() {
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec("PRAGMA foreign_keys = ON");
  for (const migration of [
    "0001_cloud_backend.sql",
    "0002_anonymous_event_details.sql",
    "0003_production_accounts.sql",
    "0004_rewarded_ads.sql",
    "0005_operational_guards.sql",
  ]) {
    sqlite.exec(readFileSync(new URL(`../migrations/${migration}`, import.meta.url), "utf8"));
  }
  return {
    database: new LocalD1(sqlite),
    dispose: () => sqlite.close(),
  };
}

class LocalD1 {
  constructor(database) { this.database = database; }
  prepare(sql) { return new LocalD1Statement(this.database, sql); }
  async batch(statements) {
    this.database.exec("BEGIN IMMEDIATE");
    try {
      const results = statements.map((statement) => statement.runSync());
      this.database.exec("COMMIT");
      return results;
    } catch (error) {
      this.database.exec("ROLLBACK");
      throw error;
    }
  }
}

class LocalD1Statement {
  constructor(database, sql, values = []) {
    this.database = database;
    this.sql = sql;
    this.values = values;
  }
  bind(...values) { return new LocalD1Statement(this.database, this.sql, values); }
  async first() { return this.database.prepare(this.sql).get(...this.values) || null; }
  async all() { return { results: this.database.prepare(this.sql).all(...this.values) }; }
  async run() { return this.runSync(); }
  runSync() {
    const result = this.database.prepare(this.sql).run(...this.values);
    return {
      meta: {
        changes: Number(result.changes || 0),
        last_row_id: Number(result.lastInsertRowid || 0),
      },
    };
  }
}
