// youtube-studio-share / env.js
// Shared base for probe.js and studio.js. Evaluate this FIRST, in a
// studio.youtube.com tab, through the browser tool's JavaScript evaluation.
// Owns the single copy of the UI strings and selectors: when Studio changes,
// STR and SEL are repaired here and nowhere else.
// Exposes: window.ytStudioEnv = { STR, SEL, sub, norm, vis, textOf, deepAll, findText,
//   controlNear, controlByText, isChecked, press, sleep, waitFor, visibleErrors }
(() => {
  // UI strings, English then Finnish. `{domain}` is substituted at call time.
  // `observed` strings were read from a live Studio session (2026-10); the
  // others are inferred and probe() reports whether they resolve.
  const STR = {
    private:        { observed: true,  text: ['Private', 'Yksityinen'] },
    sharePrivately: { observed: true,  text: ['Share privately', 'Jaa yksityisesti'] },
    shareDialog:    { observed: true,  text: ['Share video privately', 'Jaa video yksityisenä'] },
    orgAccess:      { observed: true,  text: ['Give view access to all {domain} users', 'Anna katseluoikeus kaikille {domain}-käyttäjille'] },
    notifyEmail:    { observed: true,  text: ['Notify via email', 'Ilmoita sähköpostilla'] },
    done:           { observed: true,  text: ['Done', 'Valmis'] },
    save:           { observed: true,  text: ['Save', 'Tallenna'] },
    sharedWithOrg:  { observed: true,  text: ['Shared privately with everyone at {domain}', 'Jaettu yksityisesti kaikille osoitteessa {domain}'] },
    saveToShare:    { observed: true,  text: ['(save to share)', '(tallenna jakaaksesi)'] },
    pending:        { observed: true,  text: ['Pending', 'Odottaa'] },
    hdReady:        { observed: true,  text: ['HD video ready', 'Teräväpiirtovideo valmis'] },
    oops:           { observed: true,  text: ['Oops, something went wrong', 'Hups, jotain meni pieleen'] },
    visibility:     { observed: false, text: ['Visibility', 'Näkyvyys'] },
  };

  // Structural selectors. `#textbox` and `ytcp-error-section` were observed;
  // the rest are candidates that probe() checks. Text matching through STR is
  // the fallback for every control, so a stale selector degrades, not breaks.
  const SEL = {
    textbox:       '#textbox[contenteditable="true"]',   // observed: title first, description second
    errorSection:  'ytcp-error-section',                 // observed: always present as hidden templates
    visibility:    'ytcp-video-metadata-visibility',     // candidate: the edit page's Visibility card
    privateRadio:  'tp-yt-paper-radio-button[name="PRIVATE"]', // candidate
    saveButton:    'ytcp-button#save',                   // candidate
    dialog:        'tp-yt-paper-dialog, ytcp-dialog, [role="dialog"]',
    controls:      'button, [role="button"], [role="radio"], [role="checkbox"], [role="option"], ytcp-button, tp-yt-paper-radio-button, ytcp-checkbox-lit',
  };

  const sub = (s, vars = {}) => s.replace(/\{(\w+)\}/g, (_, k) => vars[k] ?? `{${k}}`);
  const norm = s => (s || '').replace(/\s+/g, ' ').trim().toLowerCase();
  const strings = (key, vars) => STR[key].text.map(s => norm(sub(s, vars)));

  const vis = el => !!el && (el.checkVisibility
    ? el.checkVisibility({ visibilityProperty: true, opacityProperty: true })
    : el.offsetParent !== null);

  // querySelectorAll that also descends into open shadow roots. Studio's
  // Polymer elements mostly render into the light DOM, but not all of them.
  const deepAll = (sel, root = document) => {
    const out = [...root.querySelectorAll(sel)];
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
    for (let n = walker.currentNode; n; n = walker.nextNode()) {
      if (n.shadowRoot) out.push(...deepAll(sel, n.shadowRoot));
    }
    return [...new Set(out)];
  };

  // Rendered text; textContent where innerText is unavailable (non-browser DOMs).
  const textOf = el => (el.innerText ?? el.textContent ?? '');

  const ownText = el => norm(el.getAttribute?.('aria-label') || el.textContent);

  // Innermost visible elements whose text (or aria-label) matches one of the
  // key's strings. mode: 'exact' | 'prefix' | 'contains'.
  const findText = (key, { vars, root = document, mode = 'exact', visibleOnly = true } = {}) => {
    const want = strings(key, vars);
    const hit = t => want.some(w => mode === 'exact' ? t === w : mode === 'prefix' ? t.startsWith(w) : t.includes(w));
    const all = deepAll('*', root).filter(el => (!visibleOnly || vis(el)) && hit(ownText(el)));
    return all.filter(el => !all.some(other => other !== el && el.contains(other)));
  };

  // The control (role=radio/checkbox/button) that a label element belongs to:
  // the label itself, a descendant, or the nearest ancestor that holds one.
  const controlNear = (label, role) => {
    const sel = `[role="${role}"]`;
    for (let a = label, depth = 0; a && depth < 6; a = a.parentElement || a.getRootNode()?.host, depth++) {
      if (a.matches?.(sel)) return a;
      const inner = a.querySelector?.(sel) || deepAll(sel, a)[0];
      if (inner) return inner;
    }
    return null;
  };

  const controlByText = (key, role, opts = {}) => {
    for (const label of findText(key, opts)) {
      const c = controlNear(label, role);
      if (c && vis(c)) return c;
    }
    return null;
  };

  const isChecked = el => el?.getAttribute('aria-checked') === 'true' || el?.checked === true;
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  const waitFor = async (fn, { timeout = 8000, poll = 200, what = 'condition' } = {}) => {
    const t0 = Date.now();
    for (;;) {
      const v = fn();
      if (v) return v;
      if (Date.now() - t0 > timeout) throw new Error(`timed out waiting for ${what}`);
      await sleep(poll);
    }
  };

  // Click without coordinates. A plain .click() first; if `changed()` reports
  // no effect, replay the pointer sequence some Polymer controls listen for.
  // Never both for a toggle: the caller passes changed() so a checkbox is not
  // flipped twice.
  const press = async (el, changed = () => true, settle = 400) => {
    el.scrollIntoView?.({ block: 'center' });
    el.click();
    await sleep(settle);
    if (changed()) return true;
    const o = { bubbles: true, cancelable: true, composed: true, button: 0 };
    for (const t of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) {
      el.dispatchEvent(new (t.startsWith('pointer') ? PointerEvent : MouseEvent)(t, o));
    }
    await sleep(settle);
    return changed();
  };

  // Studio always carries hidden ytcp-error-section templates ("Oops,
  // something went wrong"); only a visible one is an error.
  const visibleErrors = () => deepAll(SEL.errorSection).filter(vis).map(e => textOf(e).trim().slice(0, 200));

  window.ytStudioEnv = { STR, SEL, sub, norm, vis, textOf, deepAll, findText, controlNear, controlByText, isChecked, press, sleep, waitFor, visibleErrors };
  console.log('ytStudioEnv ready; load probe.js and studio.js next');
})();
