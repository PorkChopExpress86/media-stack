'use strict';

const express = require('express');
const multer = require('multer');
const rateLimit = require('express-rate-limit');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 8055;

const SOUNDS_DIR = process.env.SOUNDS_DIR || '/data/sounds';
const CONFIG_DIR = process.env.CONFIG_DIR || '/data/config';
const CONFIG_FILE = path.join(CONFIG_DIR, 'buttons.json');

const ALLOWED_EXTENSIONS = new Set(['.mp3', '.wav', '.ogg', '.flac', '.aac', '.m4a', '.webm']);
const MAX_FILE_SIZE = 50 * 1024 * 1024; // 50 MB

// Ensure storage directories exist
[SOUNDS_DIR, CONFIG_DIR].forEach((dir) => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

// Initialize button config if it doesn't exist
if (!fs.existsSync(CONFIG_FILE)) {
  const defaultButtons = Array.from({ length: 16 }, (_, i) => ({
    id: i + 1,
    label: `Button ${i + 1}`,
    sound: null,
    color: '#4a90d9',
  }));
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(defaultButtons, null, 2));
}

// Multer storage — keep original extension, sanitize filename
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, SOUNDS_DIR),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    const base = path.basename(file.originalname, ext)
      .replace(/[^a-zA-Z0-9._-]/g, '_')
      .slice(0, 100);
    const unique = `${Date.now()}-${base}${ext}`;
    cb(null, unique);
  },
});

const fileFilter = (_req, file, cb) => {
  const ext = path.extname(file.originalname).toLowerCase();
  if (ALLOWED_EXTENSIONS.has(ext)) {
    cb(null, true);
  } else {
    cb(new Error(`Unsupported file type: ${ext}`));
  }
};

const upload = multer({ storage, fileFilter, limits: { fileSize: MAX_FILE_SIZE } });

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Rate limiters
const readLimiter = rateLimit({ windowMs: 60_000, max: 120, standardHeaders: true, legacyHeaders: false });
const uploadLimiter = rateLimit({ windowMs: 60_000, max: 30, standardHeaders: true, legacyHeaders: false });
const writeLimiter = rateLimit({ windowMs: 60_000, max: 60, standardHeaders: true, legacyHeaders: false });

// Serve uploaded sound files
app.use('/sounds', readLimiter, (req, res, next) => {
  // Only allow simple filenames — no path traversal
  const name = path.basename(req.path);
  if (name !== req.path.replace(/^\//, '')) {
    return res.status(400).json({ error: 'Invalid filename' });
  }
  const filePath = path.join(SOUNDS_DIR, name);
  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'Sound not found' });
  }
  res.sendFile(filePath);
});

// --- API routes ---

// List all uploaded sound files
app.get('/api/sounds', readLimiter, (_req, res) => {
  const files = fs.readdirSync(SOUNDS_DIR).filter((f) => {
    const ext = path.extname(f).toLowerCase();
    return ALLOWED_EXTENSIONS.has(ext);
  });
  res.json(files);
});

// Upload one or more sound files
app.post('/api/upload', uploadLimiter, upload.array('sounds', 20), (req, res) => {
  if (!req.files || req.files.length === 0) {
    return res.status(400).json({ error: 'No files uploaded' });
  }
  const uploaded = req.files.map((f) => f.filename);
  res.json({ uploaded });
});

// Delete a sound file (and remove from any button that references it)
app.delete('/api/sounds/:filename', writeLimiter, (req, res) => {
  const name = path.basename(req.params.filename);
  const filePath = path.join(SOUNDS_DIR, name);
  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'Sound not found' });
  }
  fs.unlinkSync(filePath);

  // Remove from button config
  const buttons = readButtons();
  buttons.forEach((btn) => {
    if (btn.sound === name) btn.sound = null;
  });
  writeButtons(buttons);

  res.json({ deleted: name });
});

// Get button configuration
app.get('/api/buttons', readLimiter, (_req, res) => {
  res.json(readButtons());
});

// Save button configuration
app.post('/api/buttons', writeLimiter, (req, res) => {
  const buttons = req.body;
  if (!Array.isArray(buttons)) {
    return res.status(400).json({ error: 'Expected an array of button configs' });
  }
  // Validate each button
  for (const btn of buttons) {
    if (typeof btn.id !== 'number') {
      return res.status(400).json({ error: 'Each button must have a numeric id' });
    }
    if (btn.sound !== null && typeof btn.sound !== 'string') {
      return res.status(400).json({ error: 'Button sound must be a string or null' });
    }
    // Ensure referenced sound file actually exists
    if (btn.sound) {
      const safe = path.basename(btn.sound);
      if (safe !== btn.sound) {
        return res.status(400).json({ error: `Invalid sound filename: ${btn.sound}` });
      }
      if (!fs.existsSync(path.join(SOUNDS_DIR, safe))) {
        return res.status(400).json({ error: `Sound file not found: ${btn.sound}` });
      }
    }
  }
  writeButtons(buttons);
  res.json({ saved: true });
});

// Error handler for multer and custom file-filter errors
app.use((err, _req, res, _next) => {
  const status = err instanceof multer.MulterError ? 400 : (err.status || 400);
  res.status(status).json({ error: err.message || 'Internal server error' });
});

function readButtons() {
  return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
}

function writeButtons(buttons) {
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(buttons, null, 2));
}

app.listen(PORT, () => {
  console.log(`Soundboard server running on port ${PORT}`);
});
