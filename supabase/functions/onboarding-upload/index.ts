// ============================================================
// EDGE FUNCTION: onboarding-upload   (NMAO Onboarding ‚Äî document drop-off)
// Called by: upload.html (the school owner, NO login), browser.
// JWT: Verify JWT = OFF. The signed upload token IS the auth.
//      Redeploy RE-ENABLES Verify JWT ‚Äî turn it back OFF each time.
//
// The token is the same stateless HMAC scheme used by sms-inbound /
// sms-thread: base64url(payload) + "." + base64url(HMAC-SHA256(body)),
// signed with the service role key. Payload: { pid: prospect_id, e: exp }.
// onboarding-docs (specialist side) mints/stores it; this function only
// verifies it. No new secret.
//
// Actions (POST { token, action, ... }):
//   init        -> { ok, school_name, owner_name, documents:[...], fields:{} }
//   sign        -> { filename, category, content_type, size }
//                  -> { ok, path, upload_token }  (client uploadToSignedUrl)
//   record      -> { path, category, original_name, content_type, size }
//                  -> { ok, document }
//   save_fields -> { fields:{...}, submitted?:bool }   (accreditation intake)
//                  -> { ok }
//
// Storage: private bucket 'onboarding-uploads', paths scoped to <pid>/.
// Categories: the 7 member-platform keys + any accreditation key (acc_*).
// DB: accreditation text/checkbox answers are merged into
//     prospect_schools.accreditation_intake (jsonb); a submit stamps
//     accreditation_submitted_at and nudges accreditation_status forward.
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto).
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const svc = createClient(SUPABASE_URL, SERVICE_KEY);
const enc = new TextEncoder();

const BUCKET = "onboarding-uploads";
const MAX_BYTES = 50 * 1024 * 1024; // 50 MB per file
const MEMBER_CATEGORIES = ["roster", "billing", "curriculum", "schedule", "branding", "waivers", "other"];
// Accreditation uploads use acc_* keys; accept any that match this shape.
const ACCRED_CATEGORY = /^acc_[a-z0-9_]{1,40}$/;
function normalizeCategory(c: string): string {
  const cat = String(c || "other");
  if (MEMBER_CATEGORIES.indexOf(cat) >= 0 || ACCRED_CATEGORY.test(cat)) return cat;
  return "other";
}

// Accreditation intake fields the wizard collects (whitelist ‚Äî nothing else stored).
const ACCRED_TEXT_FIELDS = [
  "mission_statement", "instructor_lineage", "owner_names", "years_in_business",
  "website_url",
  "social_instagram", "social_facebook", "social_youtube", "social_tiktok",
  "social_x", "social_linkedin", "social_other",
  "mat_cleaner", "equipment_disinfectant",
];
const ACCRED_BOOL_FIELDS = ["ack_good_standing", "ack_revocation", "ack_six_month"];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

// ‚îÄ‚îÄ Token (matches sms-inbound / sms-thread signing) ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ‚îÄ
function b64urlDecode(s: string): Uint8Array {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
async function verifyToken(token: string): Promise<{ pid: string; e?: number } | null> {
  if (!token || token.indexOf(".") < 0) return null;
  const parts = token.split(".");
  if (parts.length !== 2) return null;
  const [bodyB64, sigB64] = parts;
  const key = await crypto.subtle.importKey(
    "raw", enc.encode(SERVICE_KEY), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, enc.encode(bodyB64));
  if (b64url(new Uint8Array(mac)) !== sigB64) return null;
  let payload: any;
  try { payload = JSON.parse(new TextDecoder().decode(b64urlDecode(bodyB64))); } catch { return null; }
  if (!payload || !payload.pid) return null;
  if (payload.e && Math.floor(Date.now() / 1000) > payload.e) return null;
  return payload;
}

function safeName(name: string): string {
  const n = String(name || "file").trim().replace(/[^A-Za-z0-9._-]+/g, "_").replace(/_+/g, "_");
  return n.slice(-120) || "file";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  try {
    const body = await req.json().catch(() => ({}));
    const claim = await verifyToken(String(body.token || ""));
    if (!claim) return json({ ok: false, error: "This upload link is invalid or has expired." }, 401);
    const pid = claim.pid;

    const { data: prospect, error: pErr } = await svc.from("prospect_schools")
      .select("id, school_name, owner_name, accreditation_intake").eq("id", pid).single();
    if (pErr || !prospect) return json({ ok: false, error: "We could not find this school." }, 404);

    const action = String(body.action || "init");

    if (action === "init") {
      const { data: docs } = await svc.from("prospect_documents")
        .select("id, category, original_name, status, uploaded_at")
        .eq("prospect_id", pid).order("uploaded_at", { ascending: false });
      // Return ONLY the whitelisted intake answers the wizard needs to resume ‚Äî
      // never the whole accreditation_intake blob, which also holds bgcheck_consents
      // (signer names, IPs, user-agents) and any specialist-internal keys.
      const intake = ((prospect as any).accreditation_intake && typeof (prospect as any).accreditation_intake === "object")
        ? (prospect as any).accreditation_intake : {};
      const fields: Record<string, unknown> = {};
      for (const k of ACCRED_TEXT_FIELDS) if (k in intake) fields[k] = intake[k];
      for (const k of ACCRED_BOOL_FIELDS) if (k in intake) fields[k] = intake[k];
      return json({
        ok: true,
        school_name: prospect.school_name || "",
        owner_name: prospect.owner_name || "",
        documents: docs || [],
        fields,
      });
    }

    if (action === "sign") {
      const size = Number(body.size || 0);
      if (size > MAX_BYTES) return json({ ok: false, error: "file_too_large", max_bytes: MAX_BYTES }, 200);
      const path = pid + "/" + Date.now() + "_" + safeName(String(body.filename || "file"));
      const { data: signed, error: sErr } = await svc.storage.from(BUCKET).createSignedUploadUrl(path);
      if (sErr || !signed) return json({ ok: false, error: "Could not start the upload. Please try again." }, 200);
      return json({ ok: true, path: signed.path, upload_token: signed.token });
    }

    if (action === "record") {
      const path = String(body.path || "");
      // Must be exactly "<pid>/<safe-filename>" ‚Äî no traversal, no nested paths.
      if (!path || !new RegExp("^" + pid.replace(/[^a-zA-Z0-9-]/g, "") + "/[A-Za-z0-9._-]+$").test(path) || path.indexOf("..") >= 0) {
        return json({ ok: false, error: "bad_path" }, 200);
      }
      const category = normalizeCategory(String(body.category || "other"));
      const { data: doc, error: iErr } = await svc.from("prospect_documents").insert({
        prospect_id: pid,
        category: category,
        original_name: String(body.original_name || "").slice(0, 255) || null,
        file_path: path,
        content_type: String(body.content_type || "").slice(0, 120) || null,
        size_bytes: Number(body.size || 0) || null,
        note: String(body.note || "").slice(0, 1000) || null,
      }).select("id, category, original_name, status, uploaded_at").single();
      if (iErr) return json({ ok: false, error: "Could not save the file record." }, 200);
      return json({ ok: true, document: doc });
    }

    if (action === "save_fields") {
      const incoming = (body.fields && typeof body.fields === "object") ? body.fields : {};
      const clean: Record<string, unknown> = {};
      for (const k of ACCRED_TEXT_FIELDS) {
        if (k in incoming) clean[k] = String(incoming[k] ?? "").slice(0, 4000);
      }
      for (const k of ACCRED_BOOL_FIELDS) {
        if (k in incoming) clean[k] = incoming[k] === true;
      }
      // Merge into existing intake so partial page-by-page saves accumulate.
      const existing = ((prospect as any).accreditation_intake && typeof (prospect as any).accreditation_intake === "object")
        ? (prospect as any).accreditation_intake : {};
      const merged = Object.assign({}, existing, clean);

      const patch: Record<string, unknown> = { accreditation_intake: merged };
      // Nudge status forward only from the initial state (never override the specialist).
      const { data: cur } = await svc.from("prospect_schools").select("accreditation_status").eq("id", pid).single();
      const st = cur ? (cur as any).accreditation_status : null;
      if (!st || st === "not_started") patch.accreditation_status = "in_progress";
      if (body.submitted === true) patch.accreditation_submitted_at = new Date().toISOString();

      const { error: uErr } = await svc.from("prospect_schools").update(patch).eq("id", pid);
      if (uErr) return json({ ok: false, error: "Could not save your answers." }, 200);
      return json({ ok: true });
    }

    if (action === "add_bgcheck_consent") {
      const name = String(body.name || "").trim().slice(0, 200);
      if (name.length < 2 || body.agreed !== true) {
        return json({ ok: false, error: "Full name and agreement are required." }, 200);
      }
      const xff = req.headers.get("x-forwarded-for") || "";
      const entry = {
        name,
        signed_at: new Date().toISOString(),
        ip: xff.split(",")[0].trim().slice(0, 60),
        ua: (req.headers.get("user-agent") || "").slice(0, 200),
        agreed: true,
        // §FCRA-EVIDENCE — snapshot EXACTLY what this signer was shown + acknowledged, so the consent
        // record is self-contained and defensible (mirrors waiver_signatures.signed_template_text).
        // Null when an older frontend doesn't send them (backward-compatible).
        disclosure_version: String(body.disclosure_version || "").slice(0, 80) || null,
        disclosure_title: String(body.disclosure_title || "").slice(0, 300) || null,
        disclosure_text: String(body.disclosure_text || "").slice(0, 12000) || null,
        acknowledgment_text: String(body.acknowledgment_text || "").slice(0, 1000) || null,
        scroll_pct: (typeof body.scroll_pct === "number" && body.scroll_pct >= 0 && body.scroll_pct <= 100) ? Math.round(body.scroll_pct) : null,
      };
      const existing = ((prospect as any).accreditation_intake && typeof (prospect as any).accreditation_intake === "object")
        ? (prospect as any).accreditation_intake : {};
      const list = Array.isArray((existing as any).bgcheck_consents) ? (existing as any).bgcheck_consents : [];
      // Cap the list ‚Äî a school has a handful of instructors; this bounds JSONB growth.
      if (list.length >= 100) return json({ ok: false, error: "Too many signatures on file." }, 200);
      list.push(entry);
      const merged = Object.assign({}, existing, { bgcheck_consents: list });

      const patch: Record<string, unknown> = { accreditation_intake: merged };
      const { data: cur } = await svc.from("prospect_schools").select("accreditation_status").eq("id", pid).single();
      const st = cur ? (cur as any).accreditation_status : null;
      if (!st || st === "not_started") patch.accreditation_status = "in_progress";

      const { error: cErr } = await svc.from("prospect_schools").update(patch).eq("id", pid);
      if (cErr) return json({ ok: false, error: "Could not record the signature." }, 200);
      return json({ ok: true, count: list.length, name });
    }

    return json({ ok: false, error: "unknown_action" }, 200);
  } catch (e) {
    console.error("onboarding-upload error:", e);
    return json({ ok: false, error: "server_error" }, 200);
  }
});
