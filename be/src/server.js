const http = require('http');

const app = require('./app');
const env = require('./config/env');
const connectDB = require('./config/db');
const { initRealtime } = require('./realtime/socket');

async function bootstrap() {
  try {
    await connectDB();
    const server = http.createServer(app);
    initRealtime(server);

    server.listen(env.port, () => {
      console.log(`API listening on http://localhost:${env.port}`);
    });
  } catch (error) {
    console.error('Failed to start server:', error.message);
    process.exit(1);
  }
}

bootstrap();
