// youtube-studio-share / probe.js
// Health check BEFORE any write: reports which selectors and UI strings
// resolve on the current Studio page, which account is signed in, and whether
// a real (visible) error is showing. Requires env.js; reads whoami from
// studio.js when loaded.
// Exposes: window.ytStudioProbe({ domain })
(() => {
  const env = window.ytStudioEnv;
  if (!env) throw new Error('load scripts/env.js first');
  const { STR, SEL, deepAll, vis, findText, visibleErrors } = env;

  window.ytStudioProbe = ({ domain } = {}) => {
    const out = {
      url: location.href,
      editPage: /^\/video\/[\w-]+\/edit/.test(location.pathname),
      videoId: location.pathname.match(/^\/video\/([\w-]+)/)?.[1] || null,
      lang: document.documentElement.lang || null,
      whoami: window.ytStudio?.whoami?.() ?? 'load studio.js for whoami',
      selectors: {},
      strings: {},
      hiddenErrorTemplates: deepAll(SEL.errorSection).filter(e => !vis(e)).length,
      visibleErrors: visibleErrors(),
    };
    for (const [k, s] of Object.entries(SEL)) {
      const all = deepAll(s);
      out.selectors[k] = { total: all.length, visible: all.filter(vis).length };
    }
    // Strings that only appear after a step (the share dialog, the shared
    // card) are expected to be absent on a fresh page; probe reports, the
    // caller judges. visible = on screen now; inDom includes hidden copies.
    for (const k of Object.keys(STR)) {
      const vars = { domain: domain || '{domain}' };
      out.strings[k] = {
        observed: STR[k].observed,
        visible: findText(k, { vars, mode: 'contains' }).length,
        inDom: findText(k, { vars, mode: 'contains', visibleOnly: false }).length,
      };
    }
    const bad = [];
    if (!out.editPage) bad.push('not on https://studio.youtube.com/video/<id>/edit');
    if (out.selectors.textbox.visible < 2) bad.push(`expected 2 visible ${SEL.textbox} (title, description), found ${out.selectors.textbox.visible}`);
    if (!out.selectors.visibility.visible && !out.strings.visibility.visible) bad.push('no Visibility card by selector or label');
    if (out.visibleErrors.length) bad.push(`visible error: ${out.visibleErrors[0]}`);
    out.verdict = bad.length ? bad : 'ok';
    return out;
  };
  console.log('ytStudioProbe ready: ytStudioProbe({ domain: "example.org" })');
})();
