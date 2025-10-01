const express = require("express");
const bodyParser = require("body-parser");
const cors = require("cors");

const app = express();
const PORT = process.env.PORT || 3000;

// Chave de autenticação
const API_KEY = "Apple2502!@";

// Armazena em memória
let jobs = {
  low: [],
  mid: [],
  high: [],
  ultra: []
};

app.use(cors());
app.use(bodyParser.json());

// Middleware de autenticação
function checkAuth(req, res, next) {
  const key = req.headers["x-api-key"];
  if (key !== API_KEY) {
    return res.status(403).json({ error: "Acesso negado" });
  }
  next();
}

// Receber job (Server Hop envia aqui)
app.post("/submit", checkAuth, (req, res) => {
  const { jobId, petName, petValue, range } = req.body;
  if (!jobId || !petName || !petValue || !range) {
    return res.status(400).json({ error: "Campos inválidos" });
  }

  if (!jobs[range]) jobs[range] = [];
  jobs[range].push({
    jobId,
    petName,
    petValue,
    timestamp: Date.now()
  });

  // Mantém só últimos 20 por range
  if (jobs[range].length > 20) jobs[range].shift();

  console.log(`[Server] Novo job em ${range}: ${petName} ($${petValue}) -> ${jobId}`);
  res.json({ success: true });
});

// Retornar jobs por range (Joiner consome aqui)
app.get("/jobs/:range", checkAuth, (req, res) => {
  const range = req.params.range;
  if (!jobs[range]) return res.status(404).json({ error: "Range inválido" });
  res.json(jobs[range]);
});

app.listen(PORT, () => {
  console.log(`Servidor JSON rodando na porta ${PORT}`);
});
