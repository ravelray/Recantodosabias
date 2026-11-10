// Cria o primeiro usuário DESENVOLVEDOR. A senha é digitada na hora (não fica em arquivo nem no código).
import pg from "pg";
import bcrypt from "bcryptjs";
import readline from "node:readline";

const url = process.env.DATABASE_URL;
if (!url) { console.error("Defina DATABASE_URL."); process.exit(1); }

function ask(q, hidden = false) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    if (hidden) rl._writeToOutput = (s) => { if (s.includes(q) || s.includes("\n")) process.stdout.write(s); };
    rl.question(q, (a) => { rl.close(); resolve(a); });
  });
}

const username = (await ask("Usuário (ex.: thiago): ")).trim().toLowerCase();
const fullName = (await ask("Nome completo: ")).trim();
const pass1 = await ask("Senha (mínimo 12 caracteres): ", true);
const pass2 = await ask("Repita a senha: ", true);
if (!/^[a-z0-9._-]{3,30}$/.test(username)) { console.error("Usuário inválido."); process.exit(1); }
if (pass1.length < 12 || pass1 !== pass2) { console.error("Senha curta demais ou diferente da confirmação."); process.exit(1); }

const client = new pg.Client({ connectionString: url });
await client.connect();
const hash = await bcrypt.hash(pass1, 12);
await client.query(
  "INSERT INTO users (username, full_name, password_hash, role) VALUES ($1,$2,$3,'DESENVOLVEDOR')",
  [username, fullName, hash]
);
await client.end();
console.log("\nDesenvolvedor criado. Já pode entrar no sistema.");
