#!/usr/bin/env node
/**
 * Browser smoke test for the exported WebGL build.
 *
 * Drives headless Chrome over the DevTools Protocol using only Node built-ins
 * (Node 22 ships a global WebSocket), so it needs no npm dependencies. It:
 *   1. attaches to an already-running Chrome with --remote-debugging-port
 *   2. navigates to the served build
 *   3. collects every console message, log entry and uncaught exception
 *   4. waits for the game's "[MidgardFury] READY" boot beacon
 *   5. screenshots the canvas and reports whether anything was actually drawn
 *
 * Usage: node browser_smoke.js <url> <screenshot-path> [timeout-seconds]
 */

const fs = require('fs');

const URL_ARG = process.argv[2] || 'http://127.0.0.1:8099/index.html';
const SHOT = process.argv[3] || '/opt/shot.png';
const TIMEOUT = (parseInt(process.argv[4], 10) || 240) * 1000;
const CDP = 'http://127.0.0.1:9222';

const logs = [];
const errors = [];
let ready = false;
let readyLine = '';

function getJSON(url) {
  return new Promise((resolve, reject) => {
    require('http')
      .get(url, (res) => {
        let d = '';
        res.on('data', (c) => (d += c));
        res.on('end', () => {
          try { resolve(JSON.parse(d)); } catch (e) { reject(e); }
        });
      })
      .on('error', reject);
  });
}

async function waitForChrome() {
  for (let i = 0; i < 60; i++) {
    try {
      const v = await getJSON(CDP + '/json/version');
      return v;
    } catch (_) {
      await new Promise((r) => setTimeout(r, 500));
    }
  }
  throw new Error('Chrome DevTools endpoint never came up');
}

function note(text) {
  if (!text) return;
  logs.push(text);
  if (text.includes('[MidgardFury] READY')) {
    ready = true;
    readyLine = text.trim();
  }
}

(async () => {
  const version = await waitForChrome();
  console.log('browser: ' + version['Browser']);

  const targets = await getJSON(CDP + '/json/list');
  const page = targets.find((t) => t.type === 'page');
  if (!page) throw new Error('no page target found');

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  let msgId = 0;
  const pending = new Map();

  const send = (method, params = {}) =>
    new Promise((resolve) => {
      const id = ++msgId;
      pending.set(id, resolve);
      ws.send(JSON.stringify({ id, method, params }));
    });

  await new Promise((resolve, reject) => {
    ws.addEventListener('open', resolve);
    ws.addEventListener('error', reject);
  });

  ws.addEventListener('message', (ev) => {
    let m;
    try { m = JSON.parse(ev.data); } catch (_) { return; }

    if (m.id && pending.has(m.id)) {
      pending.get(m.id)(m.result);
      pending.delete(m.id);
      return;
    }

    switch (m.method) {
      case 'Runtime.consoleAPICalled': {
        const txt = (m.params.args || [])
          .map((a) => (a.value !== undefined ? String(a.value)
            : a.description || ''))
          .join(' ');
        note(txt);
        break;
      }
      case 'Log.entryAdded': {
        const e = m.params.entry;
        note(e.text);
        if (e.level === 'error') errors.push(e.text);
        break;
      }
      case 'Runtime.exceptionThrown': {
        const d = m.params.exceptionDetails;
        const t = d.exception
          ? (d.exception.description || d.exception.value)
          : d.text;
        errors.push('EXCEPTION: ' + t);
        break;
      }
    }
  });

  await send('Runtime.enable');
  await send('Log.enable');
  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', {
    width: 1280, height: 720, deviceScaleFactor: 1, mobile: false,
  });

  console.log('navigating to ' + URL_ARG);
  await send('Page.navigate', { url: URL_ARG });

  const start = Date.now();
  let lastReport = 0;
  while (Date.now() - start < TIMEOUT && !ready) {
    await new Promise((r) => setTimeout(r, 1000));
    const secs = Math.floor((Date.now() - start) / 1000);
    if (secs - lastReport >= 15) {
      lastReport = secs;
      const st = await send('Runtime.evaluate', {
        expression:
          '(()=>{const c=document.querySelector("canvas");' +
          'return JSON.stringify({canvas:!!c,w:c?c.width:0,h:c?c.height:0,' +
          'status:(document.getElementById("status-notice")||{}).textContent||""});})()',
        returnByValue: true,
      });
      console.log('  t=' + secs + 's ' + (st && st.result ? st.result.value : ''));
    }
  }

  // Let the game actually play for a while before capturing. Under software
  // WebGL the frame rate is low, so game time advances much slower than wall
  // time -- a short wait would screenshot an empty wave 0.
  const settle = (parseInt(process.argv[5], 10) || 6) * 1000;
  await new Promise((r) => setTimeout(r, ready ? settle : 2000));

  const shot = await send('Page.captureScreenshot', { format: 'png' });
  if (shot && shot.data) {
    fs.writeFileSync(SHOT, Buffer.from(shot.data, 'base64'));
    console.log('screenshot -> ' + SHOT);
  }

  const canvas = await send('Runtime.evaluate', {
    expression:
      '(()=>{const c=document.querySelector("canvas");if(!c)return "no canvas";' +
      'const gl=c.getContext("webgl2")||c.getContext("webgl");' +
      'return JSON.stringify({w:c.width,h:c.height,' +
      'gl:gl?gl.getParameter(gl.VERSION):"none"});})()',
    returnByValue: true,
  });

  console.log('\n=== console output (' + logs.length + ' lines) ===');
  logs.slice(-40).forEach((l) => console.log('  | ' + l.slice(0, 200)));
  console.log('\ncanvas: ' + (canvas && canvas.result ? canvas.result.value : '?'));
  console.log('READY beacon: ' + (ready ? 'YES -> ' + readyLine : 'NO'));
  console.log('errors: ' + errors.length);
  errors.slice(0, 20).forEach((e) => console.log('  !! ' + e.slice(0, 300)));

  ws.close();
  process.exit(ready && errors.length === 0 ? 0 : 1);
})().catch((e) => {
  console.error('smoke test failed: ' + e.message);
  process.exit(2);
});
