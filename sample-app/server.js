const express = require('express');
const app = express();
const PORT = process.env.PORT || 8080;

// Root endpoint
app.get('/', (req, res) => {
  res.json({ 
    message: 'Zero Trust AKS Sample API',
    endpoints: {
      hello: '/api/hello',
      health: '/healthz',
      ready: '/readyz'
    }
  });
});

// Health endpoints for Kubernetes probes
app.get('/healthz', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date() });
});

app.get('/readyz', (req, res) => {
  res.json({ status: 'ready', timestamp: new Date() });
});

// Backwards compatibility
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date() });
});

app.get('/api/hello', (req, res) => {
  res.json({ message: 'Hello from Zero Trust AKS!', environment: 'dev' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});