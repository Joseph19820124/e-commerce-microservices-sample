// Loads the configuration from config.env to process.env
require('dotenv').config({ path: './.env' });
const deals = require('./data/deals')
const products = require('./data/products')

const express = require('express');
const cors = require('cors');
const promClient = require('prom-client');
const morgan = require('morgan');
// get MongoDB driver connection
const dbo = require('./db/conn');

const PORT = process.env.PORT || 5000;
const app = express();

// Prometheus metrics
const register = new promClient.register();
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]
});

const httpRequestTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code']
});

const activeConnections = new promClient.Gauge({
  name: 'active_connections',
  help: 'Number of active connections'
});

register.registerMetric(httpRequestDuration);
register.registerMetric(httpRequestTotal);
register.registerMetric(activeConnections);

// Health check state
let isHealthy = true;
let isReady = false;

// Middleware
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

// Metrics middleware
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const route = req.route ? req.route.path : req.path;
    
    httpRequestDuration
      .labels(req.method, route, res.statusCode)
      .observe(duration);
      
    httpRequestTotal
      .labels(req.method, route, res.statusCode)
      .inc();
  });
  
  next();
});

// Health endpoints
app.get('/health', (req, res) => {
  if (isHealthy) {
    res.status(200).json({ status: 'UP', service: 'product-service', version: '1.0.0' });
  } else {
    res.status(503).json({ status: 'DOWN', service: 'product-service' });
  }
});

app.get('/health/liveness', (req, res) => {
  res.status(200).json({ status: 'UP', timestamp: new Date().toISOString() });
});

app.get('/health/readiness', (req, res) => {
  if (isReady) {
    res.status(200).json({ status: 'UP', timestamp: new Date().toISOString() });
  } else {
    res.status(503).json({ status: 'DOWN', timestamp: new Date().toISOString() });
  }
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.use('/api', require('./routes/record'));

// Global error handling
app.use(function (err, _req, res) {
  console.error(err.stack);
  res.status(500).send('Something broke!');
});

loadData = async () => {
  try {
    const dbConnect = dbo.getDb();
    
    console.log('Starting data initialization...');
    
    // Clear existing collections
    const collections = ['deals', 'products'];
    for (const collectionName of collections) {
      try {
        const collection = dbConnect.collection(collectionName);
        const deleteResult = await collection.deleteMany({});
        console.log(`Cleared ${collectionName} collection:`, deleteResult.deletedCount, 'documents');
      } catch (err) {
        console.warn(`Failed to clear ${collectionName}:`, err.message);
      }
    }
    
    // Load initial data
    const dataToLoad = [
      { collection: 'deals', records: deals.deals },
      { collection: 'products', records: products.products }
    ];
    
    for (const data of dataToLoad) {
      try {
        const collection = dbConnect.collection(data.collection);
        const insertResult = await collection.insertMany(data.records);
        console.log(`Loaded ${data.collection}:`, insertResult.insertedCount, 'documents');
      } catch (err) {
        console.error(`Failed to load ${data.collection}:`, err.message);
        throw err;
      }
    }
    
    console.log('Data initialization completed successfully');
  } catch (error) {
    console.error('Data initialization failed:', error);
    throw error;
  }
}

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  isHealthy = false;
  
  setTimeout(() => {
    console.log('Process exiting');
    process.exit(0);
  }, 5000);
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully');
  isHealthy = false;
  process.exit(0);
});

// perform a database connection when the server starts
dbo.connectToServer(function (err) {
  if (err) {
    console.error('Failed to connect to database:', err);
    isHealthy = false;
    process.exit(1);
  }

  console.log('Successfully connected to MongoDB');
  
  // start the Express server
  const server = app.listen(PORT, () => {
    console.log(`Product service is running on port: ${PORT}`);
    console.log(`Health check available at: http://localhost:${PORT}/health`);
    console.log(`Metrics available at: http://localhost:${PORT}/metrics`);
    
    loadData().then(() => {
      isReady = true;
      console.log('Service is ready to accept requests');
    }).catch(err => {
      console.error('Failed to load initial data:', err);
      isHealthy = false;
    });
  });
  
  // Track active connections
  server.on('connection', (socket) => {
    activeConnections.inc();
    socket.on('close', () => {
      activeConnections.dec();
    });
  });
});
