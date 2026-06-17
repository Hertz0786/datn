const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

const env = require('./config/env');
const apiRoutes = require('./routes');
const notFoundHandler = require('./middlewares/not-found');
const errorHandler = require('./middlewares/error-handler');

const app = express();

app.use(helmet());
app.use(
  cors({
    origin: env.clientOrigin === '*' ? true : env.clientOrigin,
  }),
);
app.use(express.json({ limit: '1mb' }));

app.use(
  '/api',
  rateLimit({
    windowMs: 60 * 1000,
    limit: 120,
    standardHeaders: true,
    legacyHeaders: false,
  }),
);

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'kiddo-social-backend',
    env: env.nodeEnv,
  });
});

app.use('/api', apiRoutes);
app.use(notFoundHandler);
app.use(errorHandler);

module.exports = app;
