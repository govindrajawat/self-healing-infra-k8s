const express = require('express');
const promClient = require('prom-client');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

// Enable CORS
app.use(cors());
app.use(express.json());

// Prometheus metrics setup
const register = promClient.register;
promClient.collectDefaultMetrics({ register });

// Custom metrics
const httpRequestsTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status']
});

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route']
});

const memoryUsage = new promClient.Gauge({
  name: 'app_memory_usage_bytes',
  help: 'Application memory usage in bytes'
});

// Global variables for failure simulation
let shouldCrash = false;
let shouldReturnErrors = false;
let memoryLeak = false;
let memoryLeakArray = [];

// Middleware to track requests
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestsTotal.inc({ method: req.method, route: req.route?.path || req.path, status: res.statusCode });
    httpRequestDuration.observe({ method: req.method, route: req.route?.path || req.path }, duration);
  });
  
  next();
});

// Health check endpoint
app.get('/health', (req, res) => {
  if (shouldCrash) {
    process.exit(1);
  }
  
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    memory: process.memoryUsage()
  });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  try {
    // Update memory usage metric
    const memUsage = process.memoryUsage();
    memoryUsage.set(memUsage.heapUsed);
    
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (err) {
    res.status(500).end(err);
  }
});

// Main API endpoints
app.get('/', (req, res) => {
  if (shouldReturnErrors && Math.random() < 0.3) {
    res.status(500).json({ error: 'Simulated server error' });
  } else {
    res.json({
      message: 'Hello from Self-Healing Demo App!',
      version: '1.0.0',
      timestamp: new Date().toISOString()
    });
  }
});

app.get('/api/data', (req, res) => {
  if (shouldReturnErrors && Math.random() < 0.2) {
    res.status(503).json({ error: 'Service temporarily unavailable' });
  } else {
    res.json({
      data: [
        { id: 1, name: 'Item 1' },
        { id: 2, name: 'Item 2' },
        { id: 3, name: 'Item 3' }
      ],
      count: 3
    });
  }
});

// Failure simulation endpoints
app.post('/simulate/crash', (req, res) => {
  shouldCrash = true;
  res.json({ message: 'Crash simulation enabled. Next health check will crash the app.' });
});

app.post('/simulate/errors', (req, res) => {
  shouldReturnErrors = true;
  res.json({ message: 'Error simulation enabled. API calls will randomly return 5xx errors.' });
});

app.post('/simulate/memory-leak', (req, res) => {
  memoryLeak = true;
  // Start memory leak
  const interval = setInterval(() => {
    if (memoryLeak) {
      memoryLeakArray.push(new Array(1000000).fill('leak'));
    } else {
      clearInterval(interval);
    }
  }, 1000);
  
  res.json({ message: 'Memory leak simulation started.' });
});

app.post('/simulate/stop', (req, res) => {
  shouldCrash = false;
  shouldReturnErrors = false;
  memoryLeak = false;
  memoryLeakArray = [];
  
  // Force garbage collection if available
  if (global.gc) {
    global.gc();
  }
  
  res.json({ message: 'All simulations stopped.' });
});

// Status endpoint
app.get('/status', (req, res) => {
  res.json({
    shouldCrash,
    shouldReturnErrors,
    memoryLeak,
    memoryLeakArrayLength: memoryLeakArray.length,
    memoryUsage: process.memoryUsage()
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

// Start server
app.listen(PORT, () => {
  console.log(`🚀 Self-Healing Demo App running on port ${PORT}`);
  console.log(`📊 Metrics available at http://localhost:${PORT}/metrics`);
  console.log(`❤️  Health check at http://localhost:${PORT}/health`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully');
  process.exit(0);
}); 