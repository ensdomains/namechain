import express from 'express';
import { createProxyMiddleware } from 'http-proxy-middleware';
import cors from 'cors';

const app = express();
const PORT = 4339;

app.use(cors({
  origin: ['http://localhost:3002'],
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
  credentials: true
}));

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'cors-proxy', timestamp: new Date().toISOString() });
});

app.use('/', createProxyMiddleware({
  target: 'http://localhost:4338',
  changeOrigin: true,
  pathRewrite: {
    '^/': '/'
  },
  onProxyRes: (proxyRes, req, res) => {
    proxyRes.headers['Access-Control-Allow-Origin'] = '*';
    proxyRes.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS';
    proxyRes.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, X-Requested-With';
    proxyRes.headers['Access-Control-Allow-Credentials'] = 'true';
  },
  onError: (err, req, res) => {
    console.error('Proxy error:', err);
    res.status(500).json({ error: 'Proxy error', message: err.message });
  }
}));

app.listen(PORT, () => {
  console.log(`CORS Proxy running on http://localhost:${PORT}`);
  console.log(`Proxying requests to Alto L2 at http://localhost:4338`);
  console.log(`CORS enabled for frontend at http://localhost:3002`);
});

process.on('SIGINT', () => {
  console.log('\nShutting down CORS Proxy...');
  process.exit(0);
});
