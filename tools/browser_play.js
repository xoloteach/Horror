#!/usr/bin/env node
/**
 * Interactive browser validation: actually plays the exported build.
 *
 * Drives the on-screen TOUCH controls via CDP Input.dispatchTouchEvent. Touch is
 * used deliberately rather than mouse+keyboard: the touch path needs no pointer
 * lock (which headless Chrome will not grant without user activation), and it
 * doubles as an end-to-end test of the virtual joystick and buttons.
 *
 * Sequence: activate touch UI -> walk -> AIM -> THROW -> RECALL, screenshotting
 * each beat so the axe can be inspected in flight, embedded, and back in hand.
 *
 * Usage: node browser_play.js <url> <outdir> [readyTimeoutSec] [settleSec]
 */

const fs = require('fs');

const URL_ARG = process.argv[2] || 'http://127.0.0.1:8099/index.html';
const OUT = process.argv[3] || '/opt/play';
const READY_TIMEOUT = (parseInt(process.argv[4], 10) || 260) * 1000;
const SETTLE = (parseInt(process.argv[5], 10) || 12) * 1000;
const CDP = 'http://127.0.0.1:9222';

const W = 1280, H = 720;
// must mirror the layout in scripts/touch_controls.gd
const BTN = {
  ATTACK: [W - 105, H - 105],
  HEAVY: [W - 238, H - 128],
  RECALL: [W - 360, H - 105],
  DODGE: [W - 122, H - 240],
  AIM: [W - 252, H - 252],
};
const STICK = [170, H - 170];

const logs = [];
const errors = [];
let ready = false;

function getJSON(url) {
  return new Promise((resolve, reject) => {
    require('http').get(url, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => { try { resolve(JSON.parse(d)); } catch (e) { reject(e); } });
    }).on('error', reject);
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  for (let i = 0; i < 60; i++) {
    try { await getJSON(CDP + '/json/version'); break; }
    catch (_) { await sleep(500); }
  }
  const targets = await getJSON(CDP + '/json/list');
  const page = targets.find((t) => t.type === 'page');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  let msgId = 0;
  const pending = new Map();
  const send = (method, params = {}) => new Promise((resolve) => {
    const id = ++msgId;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });

  await new Promise((res, rej) => {
    ws.addEventListener('open', res);
    ws.addEventListener('error', rej);
  });

  ws.addEventListener('message', (ev) => {
    let m; try { m = JSON.parse(ev.data); } catch (_) { return; }
    if (m.id && pending.has(m.id)) {
      pending.get(m.id)(m.result); pending.delete(m.id); return;
    }
    if (m.method === 'Runtime.consoleAPICalled') {
      const t = (m.params.args || []).map((a) =>
        a.value !== undefined ? String(a.value) : (a.description || '')).join(' ');
      logs.push(t);
      if (t.includes('[MidgardFury] READY')) ready = true;
    } else if (m.method === 'Log.entryAdded') {
      logs.push(m.params.entry.text);
      if (m.params.entry.level === 'error') errors.push(m.params.entry.text);
    } else if (m.method === 'Runtime.exceptionThrown') {
      const d = m.params.exceptionDetails;
      errors.push('EXCEPTION: ' + (d.exception
        ? (d.exception.description || d.exception.value) : d.text));
    }
  });

  await send('Runtime.enable');
  await send('Log.enable');
  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride',
    { width: W, height: H, deviceScaleFactor: 1, mobile: false });
  await send('Emulation.setTouchEmulationEnabled',
    { enabled: true, maxTouchPoints: 3 });

  await send('Page.navigate', { url: URL_ARG });

  const t0 = Date.now();
  while (Date.now() - t0 < READY_TIMEOUT && !ready) await sleep(1000);
  if (!ready) { console.log('NEVER BOOTED'); process.exit(2); }
  console.log('booted in ' + Math.round((Date.now() - t0) / 1000) + 's');
  await sleep(SETTLE);

  fs.mkdirSync(OUT, { recursive: true });

  async function tap(name, holdMs = 140) {
    const [x, y] = BTN[name];
    await send('Input.dispatchTouchEvent',
      { type: 'touchStart', touchPoints: [{ x, y, id: 1 }] });
    await sleep(holdMs);
    await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    console.log('  tapped ' + name);
  }

  async function dragStick(dx, dy, ms) {
    const [x, y] = STICK;
    await send('Input.dispatchTouchEvent',
      { type: 'touchStart', touchPoints: [{ x, y, id: 2 }] });
    await send('Input.dispatchTouchEvent',
      { type: 'touchMove', touchPoints: [{ x: x + dx, y: y + dy, id: 2 }] });
    await sleep(ms);
    await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    console.log('  stick released');
  }

  async function shot(tag) {
    const s = await send('Page.captureScreenshot', { format: 'png' });
    if (s && s.data) {
      const p = OUT + '/' + tag + '.png';
      fs.writeFileSync(p, Buffer.from(s.data, 'base64'));
      console.log('  shot -> ' + p);
    }
  }

  // one tap anywhere first, to flip the build into touch mode
  await send('Input.dispatchTouchEvent',
    { type: 'touchStart', touchPoints: [{ x: W - 600, y: 200, id: 9 }] });
  await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await sleep(2500);
  await shot('01_touch_ui');

  await dragStick(0, -80, 4000);      // push the stick forward = walk
  await sleep(1500);
  await shot('02_walking');

  await tap('AIM');
  await sleep(4000);
  await shot('03_aiming');

  await tap('ATTACK');                 // reads as THROW while aiming
  await sleep(2200);
  await shot('04_throw_early');
  await sleep(4500);
  await shot('05_embedded');

  await tap('RECALL');
  await sleep(1800);
  await shot('06_recall');
  await sleep(4000);
  await shot('07_caught');

  console.log('\nconsole tail:');
  logs.slice(-12).forEach((l) => console.log('  | ' + l.slice(0, 180)));
  console.log('errors: ' + errors.length);
  errors.slice(0, 10).forEach((e) => console.log('  !! ' + e.slice(0, 250)));
  ws.close();
  process.exit(errors.length === 0 ? 0 : 1);
})().catch((e) => { console.error('play failed: ' + e.message); process.exit(2); });
