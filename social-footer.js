/* ============================================================
   NMAO — shared public-page "connect" footer
   Call:  renderSocialFooter(sb, schoolId)
   - sb        : an initialized supabase client (the page already has one)
   - schoolId  : the school's uuid
   Fetches the school's socials + contact info and injects a "Follow us"
   footer at the bottom of the page. Fully conditional: each icon/link only
   shows if its value exists; the whole block is skipped if nothing is set.
   Also points the favicon at the school logo. Safe to call once per page.
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

  window.renderSocialFooter = async function (sb, schoolId, opts) {
    opts = opts || {};
    try {
      if (!sb || !schoolId) return;
      if (document.getElementById("nmao-social-footer")) return; // once only
      var r = await sb.from("schools")
        .select("name,color,logo_url,phone,email,address,city,state,website,kiosk_instagram_url,kiosk_facebook_url,kiosk_tiktok_url,kiosk_video_url")
        .eq("id", schoolId).maybeSingle();
      var s = r && r.data;
      if (!s) return;

      var GOLD = (s.color && String(s.color).trim()) || opts.accent || "#C9A84C";

      var socials = [];
      function addSocial(url, icon, label) {
        var u = norm(url);
        if (u) socials.push({ url: u, icon: icon, label: label });
      }
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

      if (!socials.length && !connect.length) return;

      var html = '<div style="border-top:1px solid #232323;background:#0a0a0a;padding:1.6rem 1.4rem 1.8rem;text-align:center;margin-top:2.5rem;font-family:inherit">';
      if (socials.length) {
        html += '<div style="color:#8a8278;letter-spacing:0.22em;font-size:11px;margin-bottom:0.9rem">FOLLOW US</div>';
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
      html += '<div style="color:#5f5b54;font-size:11px;margin-top:1.15rem">' + esc(s.name || "") + (loc ? (' &middot; ' + esc(loc)) : '') + '</div>';
      html += '</div>';

      var wrap = document.createElement("div");
      wrap.id = "nmao-social-footer";
      wrap.innerHTML = html;
      document.body.appendChild(wrap);

      if (s.logo_url && String(s.logo_url).trim()) {
        try {
          var link = document.querySelector('link[rel="icon"]') || document.createElement("link");
          link.rel = "icon";
          link.href = String(s.logo_url).trim();
          document.head.appendChild(link);
        } catch (e) {}
      }
    } catch (e) { /* footer is non-critical — never break the page */ }
  };
})();
