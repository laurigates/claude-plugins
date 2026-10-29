// Runs env.js + probe.js + studio.js against a fixture Studio edit page in
// jsdom. The fixture is modelled on the flow observed in a live session
// (English and Finnish UI); it is not a copy of Studio's real DOM, so a pass
// here proves the control flow and the safety checks, not the live
// selectors. Live verification is tracked separately.
//
// Usage: node studio-fixture.test.mjs <jsdom module dir>
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(process.argv[2] || here, 'noop.js'));
const { JSDOM } = require('jsdom');
const scripts = ['env.js', 'probe.js', 'studio.js'].map(f => readFileSync(path.join(here, '..', f), 'utf8'));

const UI = {
  en: { vis: 'Visibility', priv: 'Private', share: 'Share privately', dlg: 'Share video privately',
        org: d => `Give view access to all ${d} users`, notify: 'Notify via email', done: 'Done', save: 'Save',
        shared: d => `Shared privately with everyone at ${d} (save to share)`, oops: 'Oops, something went wrong' },
  fi: { vis: 'Näkyvyys', priv: 'Yksityinen', share: 'Jaa yksityisesti', dlg: 'Jaa video yksityisenä',
        org: d => `Anna katseluoikeus kaikille ${d}-käyttäjille`, notify: 'Ilmoita sähköpostilla', done: 'Valmis', save: 'Tallenna',
        shared: d => `Jaettu yksityisesti kaikille osoitteessa ${d} (tallenna jakaaksesi)`, oops: 'Hups, jotain meni pieleen' },
};

const page = (t, { labelDomain = 'forumvirium.fi', notifyChecked = true } = {}) => `<!doctype html><html lang="x"><body>
  <div id="textbox" contenteditable="true">Old title</div>
  <div><div id="textbox" contenteditable="true">0:00 Intro</div></div>
  <ytcp-error-section hidden><span>${t.oops}</span></ytcp-error-section>
  <ytcp-video-metadata-visibility role="button"><span>${t.vis}</span> <span id="vis-value">${t.priv}</span></ytcp-video-metadata-visibility>
  <div id="vis-popup" hidden>
    <tp-yt-paper-radio-button name="PRIVATE" role="radio" aria-checked="false">${t.priv}</tp-yt-paper-radio-button>
    <ytcp-button id="share-btn" role="button">${t.share}</ytcp-button>
    <ytcp-button id="vis-done" role="button">${t.done}</ytcp-button>
  </div>
  <tp-yt-paper-dialog id="share-dlg" hidden>
    <h2>${t.dlg}</h2>
    <input type="email">
    <ytcp-checkbox-lit><div id="org" role="checkbox" aria-checked="false"></div><span>${t.org(labelDomain)}</span></ytcp-checkbox-lit>
    <ytcp-checkbox-lit><div id="notify" role="checkbox" aria-checked="${notifyChecked}"></div><span>${t.notify}</span></ytcp-checkbox-lit>
    <ytcp-button id="dlg-done" role="button">${t.done}</ytcp-button>
  </tp-yt-paper-dialog>
  <ytcp-button id="save" role="button">${t.save}</ytcp-button>
</body></html>`;

function load(t, opts) {
  const dom = new JSDOM(page(t, opts), { runScripts: 'outside-only', pretendToBeVisual: true, url: 'https://studio.youtube.com/video/abc123/edit' });
  const w = dom.window, d = w.document, $ = s => d.querySelector(s);
  w.Element.prototype.checkVisibility = function () { return !this.closest('[hidden]'); };
  w.Element.prototype.scrollIntoView = () => {};
  w.console.log = () => {};
  w.ytcfg = { data_: { CHANNEL_ID: 'UCtest', LOGGED_IN: true, INNERTUBE_API_KEY: 'must-not-leak', ACCOUNT_SESSION_TOKEN: 'must-not-leak', SESSION_INDEX: 1 } };
  // Minimal behaviour for the fixture's controls.
  const toggle = el => el.setAttribute('aria-checked', String(el.getAttribute('aria-checked') !== 'true'));
  $('ytcp-video-metadata-visibility').addEventListener('click', () => $('#vis-popup').removeAttribute('hidden'));
  $('tp-yt-paper-radio-button').addEventListener('click', e => e.currentTarget.setAttribute('aria-checked', 'true'));
  $('#share-btn').addEventListener('click', () => $('#share-dlg').removeAttribute('hidden'));
  $('#org').addEventListener('click', e => toggle(e.currentTarget));
  $('#notify').addEventListener('click', e => toggle(e.currentTarget));
  $('#dlg-done').addEventListener('click', () => {
    $('#share-dlg').setAttribute('hidden', '');
    if ($('#org').getAttribute('aria-checked') === 'true') $('#vis-value').textContent = t.shared(opts?.labelDomain || 'forumvirium.fi');
  });
  $('#vis-done').addEventListener('click', () => $('#vis-popup').setAttribute('hidden', ''));
  $('#save').addEventListener('click', () => { $('#vis-value').textContent = $('#vis-value').textContent.replace(/ \(.*\)$/, ''); });
  // jsdom has no editing commands; emulate insertText on the selection.
  d.execCommand = (cmd, _ui, text) => {
    const r = w.getSelection().getRangeAt(0);
    r.deleteContents();
    r.insertNode(d.createTextNode(text));
    r.startContainer.normalize?.();
    return cmd === 'insertText';
  };
  for (const s of scripts) w.eval(s);
  return { w, $ };
}

for (const lang of ['en', 'fi']) {
  test(`${lang}: shareWithOrg ticks org access, unticks notify, leaves it unsaved`, async () => {
    const { w, $ } = load(UI[lang]);
    const r = await w.ytStudio.shareWithOrg({ domain: 'forumvirium.fi', timeout: 1500 });
    assert.equal($('#org').getAttribute('aria-checked'), 'true');
    assert.equal($('#notify').getAttribute('aria-checked'), 'false', 'Notify via email must end unchecked');
    assert.equal(r.unsaved, true);
    assert.match(r.visibility, /forumvirium\.fi/);
    const s = await w.ytStudio.save();
    assert.equal(s.saved, true);
    assert.doesNotMatch($('#vis-value').textContent, /\(/);
  });

  test(`${lang}: probe resolves the textboxes and ignores hidden error templates`, () => {
    const { w } = load(UI[lang]);
    const p = w.ytStudioProbe({ domain: 'forumvirium.fi' });
    assert.equal(p.verdict, 'ok');
    assert.equal(p.videoId, 'abc123');
    assert.equal(p.hiddenErrorTemplates, 1);
    assert.equal(p.visibleErrors.length, 0);
  });
}

test('a tab signed in to another Workspace fails at the org checkbox', async () => {
  const { w, $ } = load(UI.en, { labelDomain: 'example.com' });
  await assert.rejects(w.ytStudio.shareWithOrg({ domain: 'forumvirium.fi', timeout: 600 }), /grant org view access/);
  assert.equal($('#org').getAttribute('aria-checked'), 'false');
});

test('a visible error section stops shareWithOrg before any click', async () => {
  const { w, $ } = load(UI.en);
  $('ytcp-error-section').removeAttribute('hidden');
  await assert.rejects(w.ytStudio.shareWithOrg({ domain: 'forumvirium.fi', timeout: 600 }), /error before starting/);
  assert.ok($('#vis-popup').hasAttribute('hidden'));
});

test('whoami reports channel config and drops credential-shaped keys', () => {
  const { w } = load(UI.en);
  const who = w.ytStudio.whoami();
  assert.equal(who.ytcfg.CHANNEL_ID, 'UCtest');
  assert.equal(who.ytcfg.SESSION_INDEX, 1);
  assert.equal(JSON.stringify(who).includes('must-not-leak'), false);
});

test('setField replaces one word in the title and reads it back', async () => {
  const { w, $ } = load(UI.en);
  const r = await w.ytStudio.setField('title', 'New', { replace: 'Old' });
  assert.equal(r.value, 'New title');
  assert.equal($('#textbox').textContent, 'New title');
});
