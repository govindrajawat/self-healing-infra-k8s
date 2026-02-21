const express = require('express');
const promClient = require('prom-client');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// --- Prometheus metrics ---
const register = promClient.register;
promClient.collectDefaultMetrics({ register }); // includes process_cpu_seconds_total, etc.

const httpRequestsTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status']
});

const memoryGauge = new promClient.Gauge({
  name: 'app_memory_usage_bytes',
  help: 'Heap memory used by the app'
});

const crashCounter = new promClient.Counter({
  name: 'app_crash_simulations_total',
  help: 'Number of crash simulations triggered'
});

// --- Simulation state ---
let shouldCrash       = false;
let shouldReturnErrors = false;
let memoryLeak        = false;
let memoryLeakArray   = [];

// Middleware: count every request
app.use((req, res, next) => {
  res.on('finish', () => {
    httpRequestsTotal.inc({
      method: req.method,
      route: req.route?.path || req.path,
      status: res.statusCode
    });
  });
  next();
});

// --- Core endpoints ---

app.get('/health', (req, res) => {
  if (shouldCrash) {
    console.log('Crash triggered by liveness probe — exiting');
    process.exit(1);
  }
  res.json({ status: 'healthy', uptime: process.uptime() });
});

app.get('/metrics', async (req, res) => {
  memoryGauge.set(process.memoryUsage().heapUsed);
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.get('/', (req, res) => {
  if (shouldReturnErrors && Math.random() < 0.5) {
    return res.status(500).json({ error: 'Simulated 500 error' });
  }
  res.json({ message: 'Self-Healing Demo App', version: '1.0.0' });
});

app.get('/api/data', (req, res) => {
  if (shouldReturnErrors && Math.random() < 0.5) {
    return res.status(503).json({ error: 'Simulated 503 error' });
  }
  res.json({ items: ['Item 1', 'Item 2', 'Item 3'] });
});

// --- Simulation endpoints ---

app.post('/simulate/crash', (req, res) => {
  shouldCrash = true;
  crashCounter.inc();
  res.json({ message: 'Crash armed — next /health call will exit the process' });
});

app.post('/simulate/errors', (req, res) => {
  shouldReturnErrors = true;
  res.json({ message: 'Error mode ON — 50% of API calls will return 5xx' });
});

app.post('/simulate/memory-leak', (req, res) => {
  if (memoryLeak) {
    return res.json({ message: 'Memory leak already running' });
  }
  memoryLeak = true;
  const interval = setInterval(() => {
    if (!memoryLeak) { clearInterval(interval); return; }
    memoryLeakArray.push(new Array(500000).fill('x')); // ~4MB per tick
  }, 1000);
  res.json({ message: 'Memory leak started — growing ~4MB/s' });
});

app.post('/simulate/stop', (req, res) => {
  shouldCrash        = false;
  shouldReturnErrors = false;
  memoryLeak         = false;
  memoryLeakArray    = [];
  if (global.gc) global.gc();
  res.json({ message: 'All simulations stopped' });
});

// Returns the current simulation state — useful for debugging
app.get('/status', (req, res) => {
  res.json({
    shouldCrash,
    shouldReturnErrors,
    memoryLeak,
    memoryLeakMB: (memoryLeakArray.length * 4).toFixed(1),
    heapUsedMB: (process.memoryUsage().heapUsed / 1024 / 1024).toFixed(1)
  });
});

// --- Start ---
app.listen(PORT, () => {
  console.log(`Self-Healing Demo App listening on port ${PORT}`);
  console.log(`  /metrics  — Prometheus metrics`);
  console.log(`  /health   — Health check (K8s liveness probe)`);
  console.log(`  /status   — Current simulation state`);
});

process.on('SIGTERM', () => { console.log('SIGTERM — shutting down'); process.exit(0); });
process.on('SIGINT',  () => { console.log('SIGINT — shutting down');  process.exit(0); });