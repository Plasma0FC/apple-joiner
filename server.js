const express = require("express");
const bodyParser = require("body-parser");
const cors = require("cors");

const app = express();
const PORT = process.env.PORT || 8080;

// Chave de autenticação
const API_KEY = process.env.API_KEY || "Apple2502!@";  // Usar variáveis de ambiente

const RANGES = ["low", "mid", "high", "ultra"];
const MAX_JOBS_PER_RANGE = 50;
const BLACKLIST_TTL = 45 * 60 * 1000; // 45 minutos
const JOB_RETENTION_TTL = 30 * 60 * 1000; // Remove jobs antigos após 30 min

// Armazena jobs em memória por range
const jobs = RANGES.reduce((acc, range) => {
  acc[range] = new Map();
  return acc;
}, {});

let blacklist = []; // { jobId, reason, expiresAt }

app.use(cors());
app.use(bodyParser.json());

// ===============================
// Helpers
// ===============================
function checkAuth(req, res, next) {
  const key = req.headers["x-api-key"];
  if (key !== API_KEY) {
    return res.status(403).json({ error: "Acesso negado" });
  }
  return next();
}

function isValidRange(range) {
  return RANGES.includes(range);
}

function ensureRange(range) {
  if (!jobs[range]) {
    jobs[range] = new Map();
  }
  return jobs[range];
}

function addToBlacklist(jobId, reason, ttl = BLACKLIST_TTL) {
  const payload = {
    jobId,
    reason: reason || "auto",
    expiresAt: Date.now() + ttl
  };
  const idx = blacklist.findIndex((entry) => entry.jobId === jobId);
  if (idx >= 0) {
    blacklist[idx] = payload;
  } else {
    blacklist.push(payload);
  }
}

function isBlacklisted(jobId) {
  return blacklist.some((entry) => entry.jobId === jobId);
}

function cleanupBlacklist() {
  const now = Date.now();
  blacklist = blacklist.filter((entry) => entry.expiresAt > now);
}

function cleanupJobs() {
  const now = Date.now();
  for (const range of Object.keys(jobs)) {
    const rangeMap = ensureRange(range);
    for (const [jobId, job] of rangeMap.entries()) {
      if (!job.lastSeen || now - job.lastSeen > JOB_RETENTION_TTL) {
        rangeMap.delete(jobId);
      }
    }
  }
}

function trimRange(range) {
  const rangeMap = ensureRange(range);
  if (rangeMap.size <= MAX_JOBS_PER_RANGE) return;

  const orderedByAge = [...rangeMap.values()].sort((a, b) => a.lastSeen - b.lastSeen);
  while (rangeMap.size > MAX_JOBS_PER_RANGE && orderedByAge.length) {
    const oldest = orderedByAge.shift();
    rangeMap.delete(oldest.jobId);
  }
}

function serializeJobs(range) {
  return [...ensureRange(range).values()].map((job) => ({
    jobId: job.jobId,
    petName: job.petName,
    petValue: job.petValue,
    petValueRaw: job.petValueRaw,
    range: job.range,
    accountId: job.accountId,
    submittedAt: job.submittedAt,
    lastSeen: job.lastSeen
  }));
}

// ===============================
// Receber job
// ===============================
app.post("/submit", checkAuth, (req, res) => {
  const { jobId, petName, petValue, range, accountId } = req.body || {};

  if (!jobId || !petName || typeof petValue === "undefined" || !range) {
    return res.status(400).json({ error: "Campos inválidos" });
  }
  if (!isValidRange(range)) {
    return res.status(400).json({ error: "Range inválido" });
  }

  cleanupBlacklist();
  cleanupJobs();

  if (isBlacklisted(jobId)) {
    return res.json({ success: false, ignored: true, reason: "blacklisted" });
  }

  const now = Date.now();
  const numericValue = Number(petValue);
  const normalizedValue = Number.isFinite(numericValue) ? numericValue : 0;

  const jobEntry = {
    jobId,
    petName,
    petValue: normalizedValue,
    petValueRaw: petValue,
    range,
    accountId: accountId || null,
    submittedAt: now,
    lastSeen: now
  };

  ensureRange(range).set(jobId, jobEntry);
  trimRange(range);

  console.log(`[Server] Novo job em ${range}: ${petName} ($${normalizedValue.toLocaleString("en-US")}) -> ${jobId}`);

  return res.json({ success: true, stored: true });
});

// ===============================
// Retornar jobs (debug)
// ===============================
app.get("/jobs/:range", checkAuth, (req, res) => {
  const range = req.params.range;
  if (!isValidRange(range)) {
    return res.status(404).json({ error: "Range inválido" });
  }

  cleanupBlacklist();
  cleanupJobs();

  return res.json(serializeJobs(range));
});

// ===============================
// Claim exclusivo (joiners usam)
// ===============================
app.post("/jobs/claim", checkAuth, (req, res) => {
  const { range, agentId } = req.body || {};

  if (!range || !isValidRange(range)) {
    return res.status(400).json({ error: "Range inválido" });
  }

  cleanupBlacklist();
  cleanupJobs();

  const rangeMap = ensureRange(range);
  if (!rangeMap.size) {
    return res.json({ success: false, reason: "empty" });
  }

  const candidates = [...rangeMap.values()].filter((job) => !isBlacklisted(job.jobId));
  if (!candidates.length) {
    return res.json({ success: false, reason: "no_available" });
  }

  candidates.sort((a, b) => (b.petValue || 0) - (a.petValue || 0));
  const selected = candidates[0];

  rangeMap.delete(selected.jobId);
  addToBlacklist(selected.jobId, "claimed");

  console.log(`[Claim] Job ${selected.jobId} (${range}) entregue para ${agentId || "unknown"}`);

  return res.json({ success: true, job: selected });
});

// ===============================
// Blacklist manual
// ===============================
app.post("/blacklist/add", checkAuth, (req, res) => {
  const { jobId, reason } = req.body || {};
  if (!jobId) {
    return res.status(400).json({ error: "jobId inválido" });
  }

  cleanupBlacklist();
  addToBlacklist(jobId, reason || "auto");

  console.log(`[Blacklist] Job ${jobId} adicionado (${reason || "auto"})`);
  return res.json({ success: true });
});

// ===============================
// Blacklist check
// ===============================
app.get("/blacklist/check/:jobId", checkAuth, (req, res) => {
  const jobId = req.params.jobId;
  cleanupBlacklist();

  const found = blacklist.find((entry) => entry.jobId === jobId);
  if (found) {
    return res.json({ blacklisted: true, reason: found.reason, expiresAt: found.expiresAt });
  }
  return res.json({ blacklisted: false });
});

app.listen(PORT, () => {
  console.log(`Servidor AppleHub rodando na porta ${PORT}`);
});
