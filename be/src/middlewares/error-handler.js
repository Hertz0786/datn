function errorHandler(err, req, res, next) {
  const statusCode = err.statusCode || 500;
  const message = err.message || 'Internal server error.';

  if (statusCode >= 500) {
    // Keep internal details off responses while preserving server logs.
    console.error(err);
  }

  const payload = { message };
  if (statusCode < 500 && err.payload !== undefined) {
    payload.details = err.payload;
  }

  res.status(statusCode).json(payload);
}

module.exports = errorHandler;
