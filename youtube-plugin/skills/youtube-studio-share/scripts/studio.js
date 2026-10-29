// youtube-studio-share / studio.js
// Org-only sharing, field edits and read-back on a YouTube Studio video edit
// page (https://studio.youtube.com/video/<id>/edit). Requires env.js.
// Exposes: window.ytStudio = { whoami, read, selectText, typeText, setField,
//   shareWithOrg, save }
// Every function returns plain data and throws an Error naming the step that
// failed. Nothing here uses coordinates or screenshots.
(() => {
  const env = window.ytStudioEnv;
  if (!env) throw new Error('load scripts/env.js first');
  const { STR, SEL, sub, norm, vis, textOf, deepAll, findText, controlByText, isChecked, press, sleep, waitFor, visibleErrors } = env;

  // ytcfg keys worth reporting; credential-shaped keys are never returned.
  const CFG_KEYS = /CHANNEL|LOGGED_IN|SESSION_INDEX|DELEGATED|ACCOUNT|LOCALE|HL$/i;
  const SECRET_KEYS = /TOKEN|KEY|XSRF|SAPISID|COOKIE|SECRET/i;

  // Which account and channel this tab is signed in as. Read this before any
  // write: in practice the first browser profile was a personal account.
  const whoami = () => {
    const cfg = window.ytcfg?.data_ || {};
    const config = Object.fromEntries(Object.entries(cfg)
      .filter(([k, v]) => CFG_KEYS.test(k) && !SECRET_KEYS.test(k) && ['string', 'number', 'boolean'].includes(typeof v)));
    const avatar = deepAll('#avatar-btn, button[aria-label*="ccount"], button[aria-label*="ili"]').find(vis);
    return {
      url: location.href,
      urlChannelId: location.pathname.match(/\/channel\/(UC[\w-]+)/)?.[1] || null,
      authuser: new URLSearchParams(location.search).get('authuser'),
      ytcfg: config,
      avatarLabel: avatar?.getAttribute('aria-label') || avatar?.querySelector('img')?.alt || null,
    };
  };

  const textboxes = () => deepAll(SEL.textbox).filter(vis);
  const field = name => {
    const boxes = textboxes();
    const box = { title: boxes[0], description: boxes[1] }[name];
    if (!box) throw new Error(`field "${name}": found ${boxes.length} visible ${SEL.textbox}`);
    return box;
  };

  const anyText = key => findText(key, { mode: 'contains', visibleOnly: false }).length > 0;

  const visibilityText = () => {
    const flat = el => textOf(el).replace(/\s+/g, ' ').trim();
    const card = deepAll(SEL.visibility).find(vis);
    if (card) return flat(card);
    const label = findText('visibility', { mode: 'exact' })[0];
    return label?.parentElement ? flat(label.parentElement) : null;
  };

  // Read back what the page holds. Use after a reload to verify a save.
  const read = () => {
    const boxes = textboxes();
    const vt = visibilityText();
    return {
      title: boxes[0] ? textOf(boxes[0]) : null,
      description: boxes[1] ? textOf(boxes[1]) : null,
      visibility: vt,
      pending: !!vt && STR.pending.text.some(s => vt.includes(s)),
      // The HD badge text lives in a tooltip that may be hidden; any copy in
      // the DOM counts. SD processing finishes first, HD minutes later.
      hdReady: anyText('hdReady'),
      errors: visibleErrors(),
    };
  };

  // Select `target` inside a field (the whole field when omitted), as a DOM
  // Range over the text node. The browser tool can then type over it, or
  // typeText() can insert the replacement.
  const selectText = (name, target) => {
    const box = field(name);
    box.focus();
    const range = document.createRange();
    if (target == null) {
      range.selectNodeContents(box);
    } else {
      const walker = document.createTreeWalker(box, NodeFilter.SHOW_TEXT);
      let node, at = -1;
      while ((node = walker.nextNode()) && (at = node.data.indexOf(target)) < 0);
      if (at < 0) throw new Error(`field "${name}": text ${JSON.stringify(target)} not found`);
      range.setStart(node, at);
      range.setEnd(node, at + target.length);
    }
    const sel = getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
    return { field: name, selected: sel.toString() };
  };

  // Insert text at the current selection as typed input, so the editor's own
  // input handlers run and Studio marks the form dirty.
  const typeText = text => {
    if (!document.execCommand('insertText', false, text)) throw new Error('insertText was refused by the page');
    return { typed: text.length };
  };

  // Replace a whole field (or one substring of it) and read it back. The API
  // `update` subcommand is the primary path for titles and descriptions;
  // this is the fallback when the video is not editable through the API.
  const setField = async (name, text, { replace } = {}) => {
    const before = textOf(field(name));
    selectText(name, replace);
    typeText(text);
    await sleep(500);
    const after = textOf(field(name));
    const expected = replace == null ? text : before.replace(replace, text);
    if (after.trim() !== expected.trim()) {
      throw new Error(`field "${name}" did not take: got ${JSON.stringify(after.slice(0, 120))}`);
    }
    return { field: name, value: after };
  };

  const dialogOf = el => el?.closest?.(SEL.dialog) || el?.getRootNode?.()?.host?.closest?.(SEL.dialog) || null;

  const step = async (name, fn) => {
    try { return await fn(); } catch (e) { throw new Error(`shareWithOrg step "${name}": ${e.message}`); }
  };

  // Visibility -> Private -> Share privately -> tick "view access for all
  // <domain> users", keep "Notify via email" unticked -> Done. Does NOT save:
  // the card then reads "Shared privately with everyone at <domain> (save to
  // share)" and save() commits it. The domain is checked against the label,
  // so a tab signed in to the wrong Workspace fails here instead of sharing.
  const shareWithOrg = async ({ domain, timeout = 8000 } = {}) => {
    if (!domain) throw new Error('shareWithOrg needs { domain }, e.g. { domain: "forumvirium.fi" }');
    const errorsBefore = visibleErrors();
    if (errorsBefore.length) throw new Error(`page shows an error before starting: ${errorsBefore[0]}`);

    await step('open visibility', async () => {
      if (controlByText('sharePrivately', 'button') || controlByText('private', 'radio')) return;
      const opener = deepAll(SEL.visibility).find(vis) || findText('visibility', { mode: 'exact' })[0];
      if (!opener) throw new Error(`no ${SEL.visibility} and no Visibility label`);
      await press(opener, () => !!controlByText('private', 'radio') || !!deepAll(SEL.privateRadio).find(vis));
      await waitFor(() => controlByText('private', 'radio') || deepAll(SEL.privateRadio).find(vis), { what: 'the Private option', timeout });
    });

    await step('choose Private', async () => {
      const radio = deepAll(SEL.privateRadio).find(vis) || controlByText('private', 'radio');
      if (!radio) throw new Error('no Private radio');
      if (!isChecked(radio) && !(await press(radio, () => isChecked(radio)))) throw new Error('Private did not become checked');
    });

    const dialog = await step('open Share privately', async () => {
      const btn = await waitFor(() => controlByText('sharePrivately', 'button') || findText('sharePrivately')[0], { what: 'Share privately', timeout });
      await press(btn, () => findText('shareDialog').length > 0);
      const title = await waitFor(() => findText('shareDialog')[0], { what: 'the Share video privately dialog', timeout });
      return dialogOf(title) || document;
    });

    await step('grant org view access', async () => {
      const box = await waitFor(() => controlByText('orgAccess', 'checkbox', { vars: { domain }, root: dialog }),
        { what: `a checkbox labelled for ${domain}`, timeout });
      if (!isChecked(box) && !(await press(box, () => isChecked(box)))) throw new Error('org checkbox did not become checked');
    });

    await step('keep Notify via email unchecked', async () => {
      const box = controlByText('notifyEmail', 'checkbox', { root: dialog });
      if (!box) throw new Error('Notify via email checkbox not found; refusing to continue without seeing its state');
      if (isChecked(box) && !(await press(box, () => !isChecked(box)))) throw new Error('could not uncheck Notify via email');
      if (isChecked(box)) throw new Error('Notify via email is still checked');
    });

    await step('Done (share dialog)', async () => {
      const btn = controlByText('done', 'button', { root: dialog }) || findText('done', { root: dialog })[0];
      if (!btn) throw new Error('no Done button in the share dialog');
      await press(btn, () => findText('shareDialog').length === 0);
      await waitFor(() => findText('shareDialog').length === 0, { what: 'the share dialog to close', timeout });
    });

    // The visibility popup on the edit page may have its own Done.
    await step('Done (visibility)', async () => {
      const btn = controlByText('done', 'button');
      if (btn) await press(btn, () => !vis(btn));
    });

    const card = await step('read Visibility', async () =>
      waitFor(() => {
        const t = visibilityText();
        return t && STR.sharedWithOrg.text.some(s => t.includes(sub(s, { domain }))) && t;
      }, { what: `Visibility to read "Shared privately with everyone at ${domain}"`, timeout }));

    return { domain, visibility: card, unsaved: STR.saveToShare.text.some(s => card.includes(s)), errors: visibleErrors() };
  };

  // Click Save and wait until the "(save to share)" marker is gone. Verify by
  // reloading the page and calling read() — the post-save DOM is not proof.
  const save = async () => {
    const btn = deepAll(SEL.saveButton).find(vis) || controlByText('save', 'button') || findText('save')[0];
    if (!btn) throw new Error('no Save button');
    if (btn.hasAttribute('disabled') || btn.getAttribute('aria-disabled') === 'true') throw new Error('Save is disabled: nothing to save');
    await press(btn, () => !STR.saveToShare.text.some(s => (visibilityText() || '').includes(s)), 1500);
    const errors = visibleErrors();
    if (errors.length) throw new Error(`save reported: ${errors[0]}`);
    return { saved: true, visibility: visibilityText(), next: 'reload the edit page, then ytStudio.read()' };
  };

  window.ytStudio = { whoami, read, selectText, typeText, setField, shareWithOrg, save };
  console.log('ytStudio ready: ytStudio.whoami(), await ytStudio.shareWithOrg({ domain }), await ytStudio.save()');
})();
