/* ============================================================
   NMAO — shared public-page "connect" footer + share button
   Entry points:
     renderSocialFooter(sb, schoolId)            - when you have the school id
     renderSocialFooterByMembership(sb, memId)   - join/plans (resolves school id)
   Injects a footer at the bottom of the page: a "Share this page" button,
   the school's social icons, a connect row (website / directions / phone /
   email), and the school name. Everything is conditional; nothing shown if
   nothing is set. Never throws (footer is non-critical).
   ============================================================ */
(function () {
  function norm(u) {
    if (!u) return "";
    u = String(u).trim();
    if (!u) return "";
    if (!/^https?:\/\//i.test(u)) u = "https://" + u;
    return u;
  }
  function esc(s) {
    return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  window.nmaoSharePage = function () {
    var url = window.location.href;
    var title = document.title || "Take a look";
    try {
      if (navigator.share) { navigator.share({ title: title, url: url }).catch(function () {}); return; }
    } catch (e) {}
    try {
      navigator.clipboard.writeText(url).then(function () {
        var b = document.getElementById("nmao-share-btn");
        if (b) { var t = b.getAttribute("data-label") || b.textContent; b.textContent = "Link copied"; setTimeout(function () { b.innerHTML = t; }, 1600); }
      });
    } catch (e2) { window.prompt("Copy this link:", url); }
  };

  window.renderSocialFooter = async function (sb, schoolId, opts) {
    opts = opts || {};
    try {
      if (!sb || !schoolId) return;
      if (document.getElementById("nmao-social-footer")) return;
      var r = await sb.from("schools")
        .select("name,color,logo_url,phone,email,address,city,state,website,kiosk_instagram_url,kiosk_facebook_url,kiosk_tiktok_url,kiosk_video_url")
        .eq("id", schoolId).maybeSingle();
      var s = r && r.data;
      if (!s) return;

      var GOLD = (s.color && String(s.color).trim()) || opts.accent || "#C9A84C";

      var socials = [];
      function addSocial(url, icon, label) { var u = norm(url); if (u) socials.push({ url: u, icon: icon, label: label }); }
      addSocial(s.kiosk_instagram_url, "fa-instagram", "Instagram");
      addSocial(s.kiosk_facebook_url, "fa-facebook-f", "Facebook");
      addSocial(s.kiosk_tiktok_url, "fa-tiktok", "TikTok");
      addSocial(s.kiosk_video_url, "fa-youtube", "YouTube");

      var connect = [];
      var web = norm(s.website);
      if (web) connect.push({ href: web, icon: "fa-globe", label: "Website", ext: true });
      var addr = [s.address, s.city, s.state].filter(function (x) { return x && String(x).trim(); });
      if (addr.length) connect.push({ href: "https://maps.google.com/?q=" + encodeURIComponent(addr.join(", ")), icon: "fa-location-dot", label: "Get directions", ext: true });
      if (s.phone && String(s.phone).trim()) connect.push({ href: "tel:" + String(s.phone).replace(/[^0-9+]/g, ""), icon: "fa-phone", label: String(s.phone).trim() });
      if (s.email && String(s.email).trim()) connect.push({ href: "mailto:" + String(s.email).trim(), icon: "fa-envelope", label: String(s.email).trim() });

      var shareLabel = '<i class="fa-solid fa-share-nodes" style="margin-right:0.4rem"></i>Share this page';
      var html = '<div style="border-top:1px solid #232323;background:#0a0a0a;padding:1.6rem 1.4rem 1.8rem;text-align:center;margin-top:2.5rem;font-family:inherit">';
      html += '<button id="nmao-share-btn" data-label="' + shareLabel.replace(/"/g, "&quot;") + '" onclick="nmaoSharePage()" style="background:' + GOLD + ';color:#0a0a0a;border:none;border-radius:999px;padding:0.6rem 1.3rem;font-size:0.82rem;font-weight:600;letter-spacing:0.04em;cursor:pointer;font-family:inherit">' + shareLabel + '</button>';

      if (socials.length) {
        html += '<div style="color:#8a8278;letter-spacing:0.22em;font-size:11px;margin:1.4rem 0 0.9rem">FOLLOW US</div>';
        html += '<div style="display:flex;justify-content:center;gap:0.7rem;flex-wrap:wrap">';
        socials.forEach(function (it) {
          html += '<a href="' + esc(it.url) + '" target="_blank" rel="noopener noreferrer" aria-label="' + esc(it.label) + '" style="width:42px;height:42px;border:1px solid ' + GOLD + ';border-radius:50%;display:flex;align-items:center;justify-content:center;color:' + GOLD + ';text-decoration:none;font-size:18px"><i class="fa-brands ' + it.icon + '"></i></a>';
        });
        html += '</div>';
      }
      if (connect.length) {
        html += '<div style="display:flex;justify-content:center;gap:1.2rem;flex-wrap:wrap;margin-top:1.15rem">';
        connect.forEach(function (it) {
          var t = it.ext ? ' target="_blank" rel="noopener noreferrer"' : '';
          html += '<a href="' + esc(it.href) + '"' + t + ' style="color:#cfc7ba;text-decoration:none;font-size:0.8rem;white-space:nowrap"><i class="fa-solid ' + it.icon + '" style="color:' + GOLD + ';margin-right:0.35rem"></i>' + esc(it.label) + '</a>';
        });
        html += '</div>';
      }
      var loc = [s.city, s.state].filter(function (x) { return x && String(x).trim(); }).join(", ");
      html += '<div style="color:#5f5b54;font-size:11px;margin-top:1.15rem">' + esc(s.name || "") + (loc ? (" &middot; " + esc(loc)) : "") + '</div>';
      html += '</div>';

      var wrap = document.createElement("div");
      wrap.id = "nmao-social-footer";
      wrap.innerHTML = html;
      document.body.appendChild(wrap);

      if (s.logo_url && String(s.logo_url).trim()) {
        try {
          var link = document.querySelector('link[rel="icon"]') || document.createElement("link");
          link.rel = "icon"; link.href = String(s.logo_url).trim(); document.head.appendChild(link);
        } catch (e) {}
      }
    } catch (e) { }
  };

  window.renderSocialFooterByMembership = async function (sb, membershipId, opts) {
    try {
      if (!sb || !membershipId) return;
      var r = await sb.rpc("get_school_id_for_membership", { p_membership_id: membershipId });
      var sid = r && r.data;
      if (sid) window.renderSocialFooter(sb, sid, opts);
    } catch (e) { }
  };
})();
