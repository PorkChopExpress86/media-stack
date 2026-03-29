/* Shared helpers used across all pages */

let _toastTimer = null;

function showToast(msg, type = 'success') {
  const el = document.getElementById('toast');
  if (!el) return;
  el.textContent = msg;
  el.className = `show ${type}`;
  clearTimeout(_toastTimer);
  _toastTimer = setTimeout(() => { el.className = ''; }, 3000);
}

async function apiFetch(url, opts = {}) {
  const res = await fetch(url, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

function markActiveNav() {
  const page = location.pathname.replace(/\/$/, '') || '/';
  document.querySelectorAll('nav a').forEach((a) => {
    const href = a.getAttribute('href').replace(/\/$/, '') || '/';
    a.classList.toggle('active', href === page);
  });
}

document.addEventListener('DOMContentLoaded', markActiveNav);
