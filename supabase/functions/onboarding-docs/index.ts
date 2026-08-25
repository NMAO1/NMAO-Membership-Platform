// ============================================================
// EDGE FUNCTION: onboarding-docs   (NMAO Onboarding — specialist side)
// Called by: specialist.html (logged-in admin or assigned specialist).
// JWT: leave Verify JWT = ON (requires an authenticated caller; the
//      function also checks admin OR the prospect's assigned specialist).
//
// Actions (POST { action, ... }):
//   link     -> { prospect_id, email?:bool }
//               Mints (or REUSES, if still valid) a 60-day upload token,
//               stores it on prospect_schools, optionally emails the owner
//               via Resend, and returns the copyable URL.
//               -> { ok, url, emailed }
//   download -> { document_id }
//               Returns a short-lived signed download URL for one file.
//               -> { ok, url }
//
// Token: same HMAC scheme as onboarding-upload / sms-thread, signed with
//        the service role key. Payload { pid, e }. No new secret.
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY,
//          RESEND_OUTREACH_KEY (all already configured).
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const RESEND_KEY = Deno.env.get("RESEND_OUTREACH_KEY") || "";
const svc = createClient(SUPABASE_URL, SERVICE_KEY);
const enc = new TextEncoder();

const BUCKET = "onboarding-uploads";
const SITE = "https://onboard.nmao.us";
const TOKEN_TTL_DAYS = 60;
const FROM = "NMAO <outreach@outreach.nmao.us>";
const REPLY_TO = "senseibrad@nmao.us";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

// ── Token signing (matches onboarding-upload verify) ────────────────────────
function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
async function signToken(payload: Record<string, unknown>): Promise<string> {
  const bodyB64 = b64url(enc.encode(JSON.stringify(payload)));
  const key = await crypto.subtle.importKey(
    "raw", enc.encode(SERVICE_KEY), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, enc.encode(bodyB64));
  return bodyB64 + "." + b64url(new Uint8Array(mac));
}

function esc(s: string): string {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

async function emailOwner(toEmail: string, schoolName: string, url: string): Promise<boolean> {
  if (!RESEND_KEY || !toEmail) return false;
  const safeUrl = esc(url);
  const html =
    '<div style="font-family:Georgia,serif;color:#1a1a1a;line-height:1.6;max-width:560px">' +
    '<p>Hi' + (schoolName ? " " + esc(schoolName) : "") + ",</p>" +
    "<p>To help us set up your school, you can upload your existing documents " +
    "(student roster, current billing export, schedule, branding, waivers, and so on) " +
    "using your secure link below. Your onboarding specialist will take it from there.</p>" +
    '<p><a href="' + safeUrl + '" style="display:inline-block;background:#B8862C;color:#fff;' +
    'padding:0.7rem 1.2rem;text-decoration:none;border-radius:4px;font-weight:bold">Upload documents</a></p>' +
    '<p style="font-size:0.85rem;color:#555">Or paste this link into your browser:<br/>' + safeUrl + "</p>" +
    '<p style="font-size:0.85rem;color:#555">This link is private to your school and stays active for ' +
    TOKEN_TTL_DAYS + " days. No rush on anything you do not have handy yet.</p>" +
    "<p>Thank you,<br/>The NMAO Team</p></div>";
  try {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": "Bearer " + RESEND_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: FROM, to: toEmail, reply_to: REPLY_TO,
        subject: "Upload your school documents to NMAO", html: html,
      }),
    });
    const rj = await r.json().catch(() => ({}));
    return !!(r.ok && rj && rj.id);
  } catch (e) {
    console.error("emailOwner failed:", e);
    return false;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  try {
    // caller identity (admin or specialist)
    const authClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: req.headers.get("Authorization") || "" } },
    });
    const { data: ud } = await authClient.auth.getUser();
    const caller = ud && ud.user;
    if (!caller) return json({ ok: false, error: "Not signed in." }, 401);

    const body = await req.json().catch(() => ({}));
    const action = String(body.action || "");

    // §SELF-SERVE-UPLOAD — a logged-in SCHOOL OWNER mints their own upload link
    // (no specialist required). Also writes prospect_schools.member_school_id,
    // bridging the CRM prospect to the live school. Owner-authed, above the gate.
    if (action === "self_link") {
      const { data: school } = await svc.from("schools")
        .select("id, name").eq("owner_id", caller.id).maybeSingle();
      if (!school) return json({ ok: false, error: "You are not the owner of a school." }, 403);
      const ownerEmail = (caller.email || "").toLowerCase();

      let pr: any = null;
      {
        const { data } = await svc.from("prospect_schools")
          .select("id, upload_token, upload_token_expires_at")
          .eq("member_school_id", school.id).maybeSingle();
        pr = data;
      }
      if (!pr && ownerEmail) {
        const { data } = await svc.from("prospect_schools")
          .select("id, upload_token, upload_token_expires_at")
          .ilike("email", ownerEmail).maybeSingle();
        pr = data;
      }
      let pid: string;
      if (pr) {
        pid = pr.id;
        await svc.from("prospect_schools").update({ member_school_id: school.id }).eq("id", pid);
      } else {
        const { data: created, error: cErr } = await svc.from("prospect_schools")
          .insert({ school_name: school.name, email: ownerEmail || null,
                    member_school_id: school.id, status: "converted", source: "self_serve" })
          .select("id").single();
        if (cErr || !created) return json({ ok: false, error: "could_not_create_prospect" }, 200);
        pid = created.id;
        pr = { upload_token: null, upload_token_expires_at: null };
      }

      const nowSec = Math.floor(Date.now() / 1000);
      let token = pr.upload_token || "";
      const expMs = pr.upload_token_expires_at ? new Date(pr.upload_token_expires_at).getTime() : 0;
      if (!(token && expMs > Date.now() + 60000)) {
        const e = nowSec + TOKEN_TTL_DAYS * 24 * 60 * 60;
        token = await signToken({ pid: pid, e: e });
        await svc.from("prospect_schools").update({
          upload_token: token,
          upload_token_expires_at: new Date(e * 1000).toISOString(),
        }).eq("id", pid);
      }
      return json({ ok: true, url: SITE + "/upload.html?t=" + token });
    }

    const { data: meRow } = await svc.from("onboarding_specialists")
      .select("id, is_admin").eq("user_id", caller.id).single();
    if (!meRow) return json({ ok: false, error: "not_authorized" }, 403);

    // helper: authorize the caller against a prospect row
    function canAccess(prospect: any): boolean {
      return meRow.is_admin === true || prospect.assigned_specialist_id === meRow.id;
    }

    if (action === "link") {
      const pid = String(body.prospect_id || "").trim();
      if (!pid) return json({ ok: false, error: "missing_prospect" }, 200);
      const { data: p, error: pErr } = await svc.from("prospect_schools")
        .select("id, school_name, owner_name, email, assigned_specialist_id, upload_token, upload_token_expires_at")
        .eq("id", pid).single();
      if (pErr || !p) return json({ ok: false, error: "prospect_not_found" }, 200);
      if (!canAccess(p)) return json({ ok: false, error: "not_authorized" }, 403);

      // reuse the active link if still valid; otherwise mint + store a fresh one
      const nowSec = Math.floor(Date.now() / 1000);
      let token = p.upload_token || "";
      const expMs = p.upload_token_expires_at ? new Date(p.upload_token_expires_at).getTime() : 0;
      const stillValid = token && expMs > Date.now() + 60000; // small skew buffer
      if (!stillValid) {
        const e = nowSec + TOKEN_TTL_DAYS * 24 * 60 * 60;
        token = await signToken({ pid: pid, e: e });
        await svc.from("prospect_schools").update({
          upload_token: token,
          upload_token_expires_at: new Date(e * 1000).toISOString(),
        }).eq("id", pid);
      }

      const url = SITE + "/upload.html?t=" + token;
      let emailed = false;
      if (body.email !== false && p.email) emailed = await emailOwner(p.email, p.owner_name || p.school_name || "", url);
      return json({ ok: true, url: url, emailed: emailed });
    }

    if (action === "download") {
      const docId = String(body.document_id || "").trim();
      if (!docId) return json({ ok: false, error: "missing_document" }, 200);
      const { data: doc, error: dErr } = await svc.from("prospect_documents")
        .select("id, prospect_id, file_path, original_name").eq("id", docId).single();
      if (dErr || !doc) return json({ ok: false, error: "document_not_found" }, 200);
      const { data: p } = await svc.from("prospect_schools")
        .select("id, assigned_specialist_id").eq("id", doc.prospect_id).single();
      if (!p || !canAccess(p)) return json({ ok: false, error: "not_authorized" }, 403);
      const { data: signed, error: sErr } = await svc.storage.from(BUCKET)
        .createSignedUrl(doc.file_path, 3600, { download: doc.original_name || undefined });
      if (sErr || !signed) return json({ ok: false, error: "could_not_sign" }, 200);
      return json({ ok: true, url: signed.signedUrl });
    }

    return json({ ok: false, error: "unknown_action" }, 200);
  } catch (e) {
    console.error("onboarding-docs error:", e);
    return json({ ok: false, error: "server_error" }, 200);
  }
});