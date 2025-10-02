const express = require("express");
const bodyParser = require("body-parser");
const cors = require("cors");

const app = express();
const PORT = process.env.PORT || 3000;

// 🔑 Chave de autenticação
const API_KEY = "Apple2502!@";

// Armazena em memória
let jobs = {
  low: [],
  mid: [],
  high: [],
  ultra: []
};

let usedJobs = new Set(); // guarda JobIds já usados

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

// ============================
// Receber job (Server Hop envia aqui)
// ============================
app.post("/submit", checkAuth, (req, res) => {
  const { jobId, petName, petValue, range } = req.body;
  if (!jobId || !petName || !petValue || !range) {
    return res.status(400).json({ error: "Campos inválidos" });
  }

  if (!jobs[range]) jobs[range] = [];
  if (!usedJobs.has(jobId)) { // evita duplicar
    jobs[range].push({
      jobId,
      petName,
      petValue,
      timestamp: Date.now()
    });

    // Mantém só últimos 50 por range
    if (jobs[range].length > 50) jobs[range].shift();

    console.log(`[Server] Novo job em ${range}: ${petName} ($${petValue}) -> ${jobId}`);
  }

  res.json({ success: true });
});

// ============================
// Pegar próximo job disponível (joiner usa isso)
// ============================
app.get("/jobs/:range", checkAuth, (req, res) => {
  const range = req.params.range;
  if (!jobs[range]) return res.status(404).json({ error: "Range inválido" });

  // procura o primeiro que ainda não foi usado
  const available = jobs[range].find(j => !usedJobs.has(j.jobId));

  if (!available) {
    return res.json({ jobId: null });
  }

  // marca como usado imediatamente
  usedJobs.add(available.jobId);
  console.log(`[Server] JobId entregue e marcado como usado -> ${available.jobId}`);

  res.json(available);
});

app.listen(PORT, () => {
  console.log(`Servidor JSON rodando na porta ${PORT}`);
});
