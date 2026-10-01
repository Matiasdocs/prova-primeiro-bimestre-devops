"use strict";
const express = require("express");
const { Pool, types } = require("pg");
const fs = require("node:fs");

// DATE deve continuar YYYY-MM-DD, sem conversão de fuso horário.
types.setTypeParser(1082, (value) => value);
for (const name of ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD"]) {
  if (!process.env[name]) throw new Error(`Variável obrigatória: ${name}`);
}
const sslMode = process.env.DB_SSL || "false";
if (!["true", "false"].includes(sslMode)) throw new Error("DB_SSL deve ser true ou false");
if (sslMode === "true" && !process.env.DB_SSL_CA) {
  throw new Error("DB_SSL_CA é obrigatório para validar o certificado do RDS");
}
const port = Number(process.env.PORT || 3000);
const dbPort = Number(process.env.DB_PORT || 5432);
for (const value of [port, dbPort]) {
  if (!Number.isInteger(value) || value < 1 || value > 65535) throw new Error("Porta inválida");
}
const pool = new Pool({
  host: process.env.DB_HOST,
  port: dbPort,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl: sslMode === "true" ? {
    ca: fs.readFileSync(process.env.DB_SSL_CA, "utf8"),
    rejectUnauthorized: true,
  } : false,
  max: 5,
  connectionTimeoutMillis: 5000,
  idleTimeoutMillis: 30000,
  statement_timeout: 10000,
  application_name: "technova-reservas",
});
pool.on("error", (error) => console.error("Erro na conexão ociosa:", error.code || error.name));
const app = express();
app.disable("x-powered-by");
app.use(express.json({ limit: "16kb" }));

function validateReservation(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const { cliente, data, status } = body;
  if (typeof cliente !== "string" || !cliente.trim() || cliente.trim().length > 150) return null;
  if (typeof status !== "string" || !status.trim() || status.trim().length > 50) return null;
  if (typeof data !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(data) || data.startsWith("0000")) return null;
  const parsed = new Date(`${data}T00:00:00.000Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== data) return null;
  return [cliente.trim(), data, status.trim()];
}
app.param("id", (req, res, next, value) => {
  const id = Number(value);
  if (!/^[1-9]\d*$/.test(value) || !Number.isSafeInteger(id) || id > 2147483647) {
    return res.status(400).json({ erro: "ID deve ser um inteiro positivo válido" });
  }
  req.reservaId = id;
  next();
});
app.get("/health", async (req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ status: "ok", database: "ok" });
  } catch {
    res.status(503).json({ status: "unavailable", database: "unavailable" });
  }
});
app.post("/reservas", async (req, res) => {
  const values = validateReservation(req.body);
  if (!values) return res.status(400).json({ erro: "Informe cliente (1–150 caracteres), data (YYYY-MM-DD válida) e status (1–50 caracteres)" });
  const { rows } = await pool.query(
    "INSERT INTO reservas (cliente, data, status) VALUES ($1, $2, $3) RETURNING id, cliente, data, status", values,
  );
  res.location(`/reservas/${rows[0].id}`).status(201).json(rows[0]);
});
app.get("/reservas", async (req, res) => {
  const { rows } = await pool.query("SELECT id, cliente, data, status FROM reservas ORDER BY id");
  res.json(rows);
});
app.get("/reservas/:id", async (req, res) => {
  const { rows } = await pool.query("SELECT id, cliente, data, status FROM reservas WHERE id = $1", [req.reservaId]);
  if (!rows.length) return res.status(404).json({ erro: "Reserva não encontrada" });
  res.json(rows[0]);
});
app.put("/reservas/:id", async (req, res) => {
  const values = validateReservation(req.body);
  if (!values) return res.status(400).json({ erro: "PUT exige cliente, data válida (YYYY-MM-DD) e status" });
  const { rows } = await pool.query(
    "UPDATE reservas SET cliente = $1, data = $2, status = $3 WHERE id = $4 RETURNING id, cliente, data, status",
    [...values, req.reservaId],
  );
  if (!rows.length) return res.status(404).json({ erro: "Reserva não encontrada" });
  res.json(rows[0]);
});
app.delete("/reservas/:id", async (req, res) => {
  const result = await pool.query("DELETE FROM reservas WHERE id = $1 RETURNING id", [req.reservaId]);
  if (!result.rowCount) return res.status(404).json({ erro: "Reserva não encontrada" });
  res.status(204).end();
});
app.use((req, res) => res.status(404).json({ erro: "Rota não encontrada" }));
// Express 5 encaminha rejeições das rotas async a este middleware.
app.use((error, req, res, next) => {
  if (res.headersSent) return next(error);
  if (error.type === "entity.parse.failed") return res.status(400).json({ erro: "JSON inválido" });
  if (error.type === "entity.too.large") return res.status(413).json({ erro: "Corpo excede 16 KB" });
  if (["22007", "22008", "22001", "23502", "23514"].includes(error.code)) {
    return res.status(400).json({ erro: "Dados inválidos" });
  }
  if (error.code === "23505") return res.status(409).json({ erro: "Registro já existente" });
  console.error("Falha na requisição:", error.code || error.name);
  res.status(500).json({ erro: "Erro interno do servidor" });
});

let server;
let stopping = false;
async function start() {
  for (let attempt = 1; attempt <= 30; attempt++) {
    try {
      await pool.query(`CREATE TABLE IF NOT EXISTS reservas (
        id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        cliente VARCHAR(150) NOT NULL CHECK (length(trim(cliente)) > 0),
        data DATE NOT NULL,
        status VARCHAR(50) NOT NULL CHECK (length(trim(status)) > 0)
      )`);
      server = app.listen(port, "0.0.0.0", () => console.log(`API disponível na porta ${port}`));
      server.on("error", async (error) => {
        console.error("Falha ao iniciar HTTP:", error.code);
        await pool.end();
        process.exit(1);
      });
      return;
    } catch (error) {
      console.error(`Banco indisponível, tentativa ${attempt}/30:`, error.code || error.name);
      if (attempt === 30) throw error;
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }
  }
}
function shutdown() {
  if (stopping) return;
  stopping = true;
  const timeout = setTimeout(() => process.exit(1), 10000);
  timeout.unref();
  if (server) server.close(() => pool.end().then(() => process.exit(0)));
  else pool.end().then(() => process.exit(0));
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
start().catch(async () => {
  await pool.end();
  process.exit(1);
});
