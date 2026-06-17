const cloudinary = require('../config/cloudinary');
const env = require('../config/env');

function createHttpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function assertCloudinaryConfigured() {
  if (
    !env.cloudinaryCloudName ||
    !env.cloudinaryApiKey ||
    !env.cloudinaryApiSecret
  ) {
    throw createHttpError(
      500,
      'Cloudinary is not configured. Please set CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET.',
    );
  }
}

function uploadBuffer(file, { sourceType, ownerId }) {
  assertCloudinaryConfigured();

  const safeSource = String(sourceType || 'OTHER').toLowerCase();
  const folder = `${env.cloudinaryFolder}/${safeSource}/${ownerId}`;

  return new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      {
        folder,
        resource_type: 'auto',
        use_filename: true,
        unique_filename: true,
        overwrite: false,
      },
      (error, result) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(result);
      },
    );

    stream.end(file.buffer);
  });
}

async function destroyMediaAsset(asset) {
  assertCloudinaryConfigured();

  if (!asset?.publicId) {
    return;
  }

  await cloudinary.uploader.destroy(asset.publicId, {
    resource_type: asset.resourceType || 'image',
    invalidate: true,
  });
}

module.exports = {
  destroyMediaAsset,
  uploadBuffer,
};
