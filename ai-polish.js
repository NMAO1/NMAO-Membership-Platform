/* =====================================================================
   ai-polish.js — reusable "✨ Polish" AI writing helper for description fields.
   Usage (after the Supabase client `sb` exists):
       attachPolish('#evDescription', { kind: 'event' });
   kinds: event | class | pack | program | generic
   Calls the polish-text edge function; non-destructive (preview before use).
   ===================================================================== */
(function () {
  var TONES = [
    ['friendly', 'Friendly'], ['professional', 'Professional'], ['philosophical', 'Philosophical'],
    ['motivational', 'Motivational'], ['concise', 'Concise'], ['grammar', 'Fix grammar'],
  ];
  var LS_KEY = 'nmao_polish_tone';
  var openPop = null;

  function css() {
    if (document.getElementById('ai-polish-css')) return;
    var s = document.createElement('style'); s.id = 'ai-polish-css';
    s.textContent =
      '.ai-polish-btn{margin-top:6px;font:600 .7rem var(--font-ui,sans-serif);letter-spacing:.08em;text-transform:uppercase;color:var(--gold,#C9A84C);background:none;border:1px solid var(--gold,#C9A84C);border-radius:6px;padding:.32rem .68rem;cursor:pointer;display:inline-flex;align-items:center;gap:5px}' +
      '.ai-polish-btn:hover{background:rgba(201,168,76,.12)}' +
      '.ai-polish-pop{position:absolute;z-index:99999;width:520px;max-width:94vw;background:var(--surface,#17161a);border:1px solid var(--gold,#C9A84C);border-radius:10px;box-shadow:0 14px 44px rgba(0,0,0,.6);padding:18px;font-family:var(--font-ui,sans-serif);color:var(--muted,#cfcfcf)}' +
      '.ai-polish-pop h4{margin:0 0 9px;font-size:.68rem;letter-spacing:.14em;text-transform:uppercase;color:var(--gold,#C9A84C)}' +
      '.ai-polish-tones{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:10px}' +
      '.ai-polish-tone{font-size:.72rem;padding:.3rem .6rem;border-radius:99px;border:1px solid var(--border,#333);background:var(--black,#0e0e12);color:var(--muted,#cfcfcf);cursor:pointer}' +
      '.ai-polish-tone.on{border-color:var(--gold,#C9A84C);color:var(--gold,#C9A84C);background:rgba(201,168,76,.14);font-weight:600}' +
      '.ai-polish-hint{width:100%;box-sizing:border-box;background:var(--black,#0e0e12);border:1px solid var(--border,#333);color:inherit;border-radius:7px;padding:8px;font:inherit;font-size:.82rem;margin-bottom:9px}' +
      '.ai-polish-preview{background:var(--black,#0e0e12);border:1px solid var(--border,#333);border-radius:7px;padding:13px 14px;font-size:.95rem;line-height:1.6;color:#e9e9e9;white-space:pre-wrap;margin:2px 0 12px;max-height:46vh;overflow:auto}' +
      '.ai-polish-row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}' +
      '.ai-polish-do{font:600 .72rem var(--font-ui,sans-serif);letter-spacing:.06em;text-transform:uppercase;color:var(--black,#141210);background:var(--gold,#C9A84C);border:none;border-radius:7px;padding:.5rem .85rem;cursor:pointer}' +
      '.ai-polish-do.ghost{color:var(--muted,#cfcfcf);background:none;border:1px solid var(--border,#333)}' +
      '.ai-polish-do:disabled{opacity:.5;cursor:default}' +
      '.ai-polish-x{background:none;border:none;color:var(--muted,#999);cursor:pointer;font-size:1rem;line-height:1;padding:2px 4px;float:right;margin-top:-4px}' +
      '.ai-polish-msg{font-size:.78rem;margin-top:7px}' +
      '.ai-polish-msg.err{color:#e08a8a}.ai-polish-msg.ok{color:var(--gold,#C9A84C)}';
    document.head.appendChild(s);
  }

  function closePop() { if (openPop) { openPop.remove(); openPop = null; document.removeEventListener('mousedown', onDoc, true); } }
  function onDoc(e) { if (openPop && !openPop.contains(e.target) && !e.target.classList.contains('ai-polish-btn')) closePop(); }

  async function call(text, tone, kind, mode) {
    var sb = window.sb;
    if (!sb || !sb.functions) throw new Error('Sign in first.');
    var res = await sb.functions.invoke('polish-text', { body: { text: text, tone: tone, kind: kind, mode: mode } });
    if (res.error) throw new Error(res.error.message || 'AI request failed.');
    var d = res.data;
    if (!d || !d.ok) throw new Error((d && d.error) || 'AI help failed.');
    return d.result;
  }

  function openPanel(ta, kind, btn) {
    closePop();
    css();
    var tone = localStorage.getItem(LS_KEY) || 'friendly';
    var pop = document.createElement('div'); pop.className = 'ai-polish-pop';
    pop.innerHTML =
      '<button type="button" class="ai-polish-x" title="Close">×</button>' +
      '<h4>✨ Improve this text</h4>' +
      '<div class="ai-polish-tones">' + TONES.map(function (t) {
        return '<button type="button" class="ai-polish-tone' + (t[0] === tone ? ' on' : '') + '" data-tone="' + t[0] + '">' + t[1] + '</button>';
      }).join('') + '</div>' +
      '<input class="ai-polish-hint" placeholder="Optional: a few words to draft from…" />' +
      '<div class="ai-polish-body"></div>' +
      '<div class="ai-polish-row">' +
        '<button type="button" class="ai-polish-do" data-mode="improve">Improve current</button>' +
        '<button type="button" class="ai-polish-do ghost" data-mode="draft">Draft from hint</button>' +
      '</div>' +
      '<div class="ai-polish-msg" hidden></div>';
    document.body.appendChild(pop);
    var r = btn.getBoundingClientRect();
    pop.style.top = (window.scrollY + r.bottom + 6) + 'px';
    pop.style.left = (window.scrollX + Math.max(8, Math.min(r.left, window.innerWidth - 540))) + 'px';
    openPop = pop;
    setTimeout(function () { document.addEventListener('mousedown', onDoc, true); }, 0);

    var msg = pop.querySelector('.ai-polish-msg');
    var body = pop.querySelector('.ai-polish-body');
    var hint = pop.querySelector('.ai-polish-hint');
    function setMsg(t, cls) { msg.textContent = t || ''; msg.className = 'ai-polish-msg ' + (cls || ''); msg.hidden = !t; }

    pop.querySelector('.ai-polish-x').onclick = closePop;
    pop.querySelectorAll('.ai-polish-tone').forEach(function (c) {
      c.onclick = function () {
        tone = c.dataset.tone; localStorage.setItem(LS_KEY, tone);
        pop.querySelectorAll('.ai-polish-tone').forEach(function (x) { x.classList.toggle('on', x === c); });
      };
    });

    function showPreview(result, mode) {
      body.innerHTML =
        '<div class="ai-polish-preview"></div>' +
        '<div class="ai-polish-row">' +
          '<button type="button" class="ai-polish-do" data-act="use">Use it</button>' +
          '<button type="button" class="ai-polish-do ghost" data-act="again">Try again</button>' +
        '</div>';
      body.querySelector('.ai-polish-preview').textContent = result;
      body.querySelector('[data-act="use"]').onclick = function () {
        ta.value = result;
        ta.dispatchEvent(new Event('input', { bubbles: true }));
        ta.dispatchEvent(new Event('change', { bubbles: true }));
        closePop();
      };
      body.querySelector('[data-act="again"]').onclick = function () { run(mode); };
    }

    async function run(mode) {
      var text = mode === 'draft' ? hint.value.trim() : ta.value.trim();
      if (mode === 'improve' && !text) { setMsg('Nothing to improve — type some text, or draft from a hint.', 'err'); return; }
      if (mode === 'draft' && !text) { setMsg('Add a few words in the hint box to draft from.', 'err'); return; }
      setMsg('Thinking…', 'ok');
      pop.querySelectorAll('.ai-polish-do').forEach(function (b) { b.disabled = true; });
      try {
        var result = await call(text, tone, kind, mode);
        setMsg('', '');
        showPreview(result, mode);
      } catch (e) {
        setMsg(e.message || 'Something went wrong.', 'err');
        pop.querySelectorAll('.ai-polish-do').forEach(function (b) { b.disabled = false; });
      }
    }

    pop.querySelectorAll('.ai-polish-row .ai-polish-do[data-mode]').forEach(function (b) {
      b.onclick = function () { run(b.dataset.mode); };
    });
  }

  window.attachPolish = function (selector, opts) {
    opts = opts || {};
    var kind = opts.kind || 'generic';
    document.querySelectorAll(selector).forEach(function (ta) {
      if (!ta || ta.dataset.polishAttached) return;
      ta.dataset.polishAttached = '1';
      css();
      var btn = document.createElement('button');
      btn.type = 'button'; btn.className = 'ai-polish-btn'; btn.innerHTML = '✨ Polish';
      btn.title = 'Improve or draft this description with AI';
      btn.onclick = function () { openPanel(ta, kind, btn); };
      ta.insertAdjacentElement('afterend', btn);
    });
  };
})();
