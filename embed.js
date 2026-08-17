/* NMAO embed auto-resize (parent-side).
 * Paste alongside an NMAO schedule/membership iframe; this listens for the height the
 * embedded page reports (postMessage {nmaoEmbed:true, height}) and resizes the matching
 * iframe so there's never an inner scrollbar. Safe no-op if no NMAO iframe is present. */
(function () {
  if (window.__nmaoEmbedResize) return;
  window.__nmaoEmbedResize = true;
  window.addEventListener('message', function (e) {
    var d = e && e.data;
    if (!d || d.nmaoEmbed !== true || typeof d.height !== 'number') return;
    var frames = document.getElementsByTagName('iframe');
    for (var i = 0; i < frames.length; i++) {
      try {
        if (frames[i].contentWindow === e.source) {
          frames[i].style.height = Math.max(1, Math.ceil(d.height)) + 'px';
          return;
        }
      } catch (_) { /* cross-origin sibling — ignore */ }
    }
  });
})();
