// Aplica os arquivos de /migrations em ordem, uma única vez cada.
import pg from "pg";
import fs from "node:fs";
import path from "node:path";

const url = process.env.DATABASE_URL;
if (!url) { console.error("Defina DATABASE_URL."); process.exit(1); }
const client = new pg.Client({ connectionString: url });
await client.connect();
await client.query("CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())");
const dir = path.join(process.cwd(), "migrations");
for (const f of fs.readdirSync(dir).filter((x) => x.endsWith(".sql")).sort()) {
  const done = await client.query("SELECT 1 FROM schema_migrations WHERE name=$1", [f]);
  if (done.rowCount) { console.log("já aplicada:", f); continue; }
  console.log("aplicando:", f);
  try {
    await client.query("BEGIN");
    await client.query(fs.readFileSync(path.join(dir, f), "utf8"));
    await client.query("INSERT INTO schema_migrations(name) VALUES ($1)", [f]);
    await client.query("COMMIT");
  } catch (e) { await client.query("ROLLBACK"); console.error("Falhou:", e.message); process.exit(1); }
}
await client.end();
console.log("Migrations concluídas.");
