/* server.js */
const express = require("express");
const morgan = require("morgan");

const PORT = process.env.PORT || 8080;
const API_KEY = process.env.API_KEY || "Apple2502!@";
const CLAIM_TTL_MS = Number(process.env.CLAIM_TTL_MS || 120000); // 2 min
const VISITED_TTL_MS = Number(process.env.VISITED_TTL_MS || 45 * 60 * 1000); // 45 min
const CLEANUP_INTERVAL_MS = Number(process.env.CLEANUP_INTERVAL_MS || 30000);

const app = express();
app.use(express.json({ limit: "256kb" }));
app.use(morgan("tiny"));

const claims = new Map();            // key => claim record
const visited = new Map();           // key => visited record
const accountAssignments = new Map();// accountId => key

const now = () => Date.now();
const jobKey = (placeId, jobId) => `${placeId}:${jobId}`;

const safeRecord = (record) => {
  if (!record) return null;
  const { metadata, ...rest } = record;
  return {
    ...rest,
    metadata: metadata || {},
  };
};

const cleanup = () => {
  const ts = now();

  for (const [key, record] of claims) {
    if (record.expiresAt <= ts) {
      claims.delete(key);
      if (accountAssignments.get(record.accountId) === key) {
        accountAssignments.delete(record.accountId);
      }
    }
  }

  for (const [key, record] of visited) {
    if (record.expiresAt <= ts) {
      visited.delete(key);
    }
  }
};

setInterval(cleanup, CLEANUP_INTERVAL_MS).unref();

app.get("/health", (_req, res) => {
  cleanup();
  res.json({ ok: true, claims: claims.size, visited: visited.size });
});

app.use((req, res, next) => {
  if (req.path === "/health") {
    return next();
  }
  const headerKey = req.get("x-api-key") || req.query.key;
  if (headerKey !== API_KEY) {
    return res.status(401).json({ ok: false, error: "invalid_api_key" });
  }
  next();
});

app.get("/blacklist/check/:jobId", (req, res) => {
  cleanup();
  const placeId = req.query.placeId || "global";
  const key = jobKey(placeId, req.params.jobId);

  const active = claims.get(key);
  if (active) {
    return res.json({
      ok: true,
      blocked: true,
      reason: "claimed",
      record: safeRecord(active),
    });
  }

  const history = visited.get(key);
  if (history) {
    return res.json({
      ok: true,
      blocked: true,
      reason: "visited",
      record: safeRecord(history),
    });
  }

  res.json({ ok: true, blocked: false });
});

app.post("/blacklist/claim", (req, res) => {
  cleanup();
  const { placeId, jobId, accountId, username, metadata } = req.body;
  if (!placeId || !jobId || !accountId) {
    return res.status(400).json({ ok: false, error: "missing_fields" });
  }

  const key = jobKey(placeId, jobId);
  const ts = now();

  const visitRecord = visited.get(key);
  if (visitRecord && visitRecord.expiresAt > ts) {
    return res.status(409).json({
      ok: false,
      reason: "visited",
      record: safeRecord(visitRecord),
    });
  }

  const existing = claims.get(key);
  if (existing && existing.accountId !== accountId && existing.expiresAt > ts) {
    return res.status(409).json({
      ok: false,
      reason: "claimed",
      record: safeRecord(existing),
    });
  }

  const expiresAt = ts + CLAIM_TTL_MS;
  const claim = {
    placeId,
    jobId,
    accountId,
    username: username || "unknown",
    metadata: {
      ...(existing ? existing.metadata : {}),
      ...(metadata || {}),
    },
    createdAt: existing ? existing.createdAt : ts,
    updatedAt: ts,
    expiresAt,
  };

  claims.set(key, claim);
  accountAssignments.set(accountId, key);

  res.status(existing ? 200 : 201).json({
    ok: true,
    expiresAt,
    record: safeRecord(claim),
  });
});

app.post("/blacklist/heartbeat", (req, res) => {
  cleanup();
  const { placeId, jobId, accountId, metadata } = req.body;
  if (!placeId || !jobId || !accountId) {
    return res.status(400).json({ ok: false, error: "missing_fields" });
  }

  const key = jobKey(placeId, jobId);
  const claim = claims.get(key);
  if (!claim || claim.accountId !== accountId) {
    return res.status(404).json({ ok: false, error: "claim_not_found" });
  }

  const ts = now();
  claim.expiresAt = ts + CLAIM_TTL_MS;
  claim.updatedAt = ts;
  if (metadata) {
    claim.metadata = { ...(claim.metadata || {}), ...metadata };
  }

  res.json({ ok: true, expiresAt: claim.expiresAt, record: safeRecord(claim) });
});

app.post("/blacklist/complete", (req, res) => {
  cleanup();
  const { placeId, jobId, accountId, username, metadata, holdForMinutes } = req.body;
  if (!placeId || !jobId) {
    return res.status(400).json({ ok: false, error: "missing_fields" });
  }

  const key = jobKey(placeId, jobId);
  const ts = now();
  const ttl = Math.max(1, Number(holdForMinutes) || (VISITED_TTL_MS / 60000)) * 60 * 1000;

  const claim = claims.get(key);
  const baseMetadata = claim ? claim.metadata : undefined;

  claims.delete(key);
  if (accountId && accountAssignments.get(accountId) === key) {
    accountAssignments.delete(accountId);
  }

  const record = {
    placeId,
    jobId,
    accountId: accountId || (claim && claim.accountId),
    username: username || (claim && claim.username) || "unknown",
    metadata: {
      ...(baseMetadata || {}),
      ...(metadata || {}),
    },
    visitedAt: ts,
    expiresAt: ts + ttl,
  };

  visited.set(key, record);
  res.json({ ok: true, expiresAt: record.expiresAt, record: safeRecord(record) });
});

app.post("/blacklist/report", (req, res) => {
  cleanup();
  const { placeId, jobId, metadata } = req.body;
  if (!placeId || !jobId || !metadata) {
    return res.status(400).json({ ok: false, error: "missing_fields" });
  }

  const key = jobKey(placeId, jobId);
  const target = claims.get(key) || visited.get(key);
  if (!target) {
    return res.status(404).json({ ok: false, error: "job_unknown" });
  }

  target.metadata = { ...(target.metadata || {}), ...metadata };
  target.updatedAt = now();

  res.json({ ok: true, record: safeRecord(target) });
});

app.listen(PORT, () => {
  console.log(`[apple-joiner] listening on :${PORT}`);
});
