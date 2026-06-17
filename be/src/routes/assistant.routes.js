const express = require('express');

const asyncHandler = require('../utils/async-handler');
const { requireAuth } = require('../middlewares/auth');
const { assertContentAllowed } = require('../services/content-moderation');
const { callAssistant } = require('../services/llm-assistant');

const router = express.Router();

router.use(requireAuth);

router.post(
  '/chat',
  asyncHandler(async (req, res) => {
    const message = String(req.body.message || '').trim();
    const history = Array.isArray(req.body.history) ? req.body.history : [];

    if (!message) {
      return res.status(400).json({ message: 'message is required.' });
    }
    if (message.length > 1200) {
      return res.status(400).json({ message: 'message is too long.' });
    }

    await assertContentAllowed({
      text: message,
      userId: req.user.id,
      targetType: 'MESSAGE',
      targetId: `assistant:${req.user.id}:${Date.now()}`,
      action: 'ask the AI assistant',
    });

    const result = await callAssistant({ message, history });

    return res.json({
      message: 'Assistant replied.',
      reply: result.reply,
      provider: result.provider,
      model: result.model,
    });
  }),
);

module.exports = router;
