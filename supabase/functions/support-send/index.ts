// ============================================================
// EDGE FUNCTION: support-send   (Member dashboard → NMAO support desk)
// Called by: dashboard.html support chat bubble (logged-in school owner /
//            instructor, browser, CORS). Verify JWT ON.
//
// Stores the school's message in the shared support thread (one per school) and
// FANS OUT an email to the whole team — every active onboarding_specialist plus
// the primary addresses — each with a one-click tokenized reply link.
//
// ERROR REPORTS: when kind='error', the message carries screenshot attachment(s)
// + "what were you trying to do", the email is flagged urgent, AND an SMS alert
// is texted to the NMAO lead so errors are handled as fast as possible.
//
// Input:  { school_id, body, kind?, attachments? }   (Authorization: Bearer <user jwt>)
// Output: { ok:true, thread_id } | { ok:false, error }
// ============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const RESEND_KEY = Deno.env.get("RESEND_OUTREACH_KEY") || "";
const TWILIO_SID = Deno.env.get("TWILIO_ACCOUNT_SID") || "";
const TWILIO_TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN") || "";
const TWILIO_FROM = Deno.env.get("TWILIO_PHONE_NUMBER") || "";

const FROM = "NMAO Support <outreach@outreach.nmao.us>";
const PRIMARY = ["senseibrad@nmao.us", "support@nmao.us"]; // always notified
const ERROR_SMS_TO = "+15163036972";                        // NMAO lead — urgent error alerts
const REPLY_BASE = "https://app.nmao.us/support-reply.html";
const UPLOAD_PREFIX = SUPABASE_URL + "/storage/v1/object/public/support-uploads/";

const svc = createClient(SUPABASE_URL, SERVICE_KEY);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
function esc(s: string): string {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

async function emailTeam(to: string, schoolName: string, msg: string, replyUrl: string, isError: boolean, shots: string[]): Promise<boolean> {
  if (!RESEND_KEY || !to) return false;
  const safeUrl = esc(replyUrl);
  const shotsHtml = shots.map((u) =>
    '<a href="' + esc(u) + '"><img src="' + esc(u) + '" alt="screenshot" style="max-width:100%;border:1px solid #ccc;border-radius:6px;margin:0.4rem 0"/></a>').join("");
  const html =
    '<div style="font-family:Georgia,serif;color:#1a1a1a;line-height:1.6;max-width:600px">' +
    (isError
      ? '<p style="font-size:0.8rem;letter-spacing:0.12em;text-transform:uppercase;color:#C0392B;font-weight:bold;margin:0 0 0.3rem">⚠️ Error report — please handle fast</p>'
      : '<p style="font-size:0.8rem;letter-spacing:0.12em;text-transform:uppercase;color:#B8862C;margin:0 0 0.3rem">New support question</p>') +
    "<p><strong>" + esc(schoolName || "A school") + "</strong> " + (isError ? "reported an error:" : "sent a message to NMAO support:") + "</p>" +
    '<blockquote style="margin:0.6rem 0;padding:0.75rem 1rem;background:#f6f3ec;border-left:3px solid ' + (isError ? "#C0392B" : "#B8862C") + ';white-space:pre-wrap">' +
    esc(msg) + "</blockquote>" +
    shotsHtml +
    '<p style="margin-top:0.8rem"><a href="' + safeUrl + '" style="display:inline-block;background:' + (isError ? "#C0392B" : "#B8862C") + ';color:#fff;' +
    'padding:0.7rem 1.2rem;text-decoration:none;border-radius:4px;font-weight:bold">Open &amp; reply</a></p>' +
    '<p style="font-size:0.82rem;color:#555">The first teammate to reply claims the thread, so we never double up or miss one.</p>' +
    "<p>— NMAO Support Desk</p></div>";
  try {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": "Bearer " + RESEND_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: FROM, to, reply_to: "support@nmao.us",
        subject: (isError ? "⚠️ ERROR — " : "Support question — ") + (schoolName || "a school"), html,
      }),
    });
    const rj = await r.json().catch(() => ({}));
    return !!(r.ok && rj && rj.id);
  } catch (e) {
    console.error("emailTeam failed:", e);
    return false;
  }
}

async function sendAlertSms(text: string): Promise<boolean> {
  if (!TWILIO_SID || !TWILIO_TOKEN || !TWILIO_FROM) { console.warn("Twilio not configured — skipping SMS alert"); return false; }
  try {
    const form = new URLSearchParams({ To: ERROR_SMS_TO, From: TWILIO_FROM, Body: text.slice(0, 480) });
    const r = await fetch("https://api.twilio.com/2010-04-01/Accounts/" + TWILIO_SID + "/Messages.json", {
      method: "POST",
      headers: {
        "Authorization": "Basic " + btoa(TWILIO_SID + ":" + TWILIO_TOKEN),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: form.toString(),
    });
    if (!r.ok) console.error("Twilio SMS failed:", r.status, await r.text().catch(() => ""));
    return r.ok;
  } catch (e) {
    console.error("sendAlertSms failed:", e);
    return false;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const authClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } } });
    const { data: userData } = await authClient.auth.getUser();
    const caller = userData && userData.user;
    if (!caller) return json({ ok: false, error: "Not signed in." }, 401);

    const body = await req.json().catch(() => ({}));
    const schoolId = String(body.school_id || "").trim();
    const msg = String(body.body || "").trim();
    const isError = String(body.kind || "") === "error";
    // only accept attachment URLs that live in our own public bucket
    const attachments: string[] = Array.isArray(body.attachments)
      ? body.attachments.map((a: unknown) => String(a || "")).filter((u: string) => u.startsWith(UPLOAD_PREFIX)).slice(0, 6)
      : [];
    if (!schoolId) return json({ ok: false, error: "Missing school." }, 200);
    if (!msg) return json({ ok: false, error: isError ? "Please describe what you were doing." : "Your message is empty." }, 200);
    if (msg.length > 4000) return json({ ok: false, error: "Message is too long (max 4000 characters)." }, 200);

    const { data: school } = await svc.from("schools")
      .select("id,name,owner_id,email").eq("id", schoolId).maybeSingle();
    if (!school) return json({ ok: false, error: "School not found." }, 200);

    let allowed = school.owner_id === caller.id;
    if (!allowed) {
      const emailNorm = String(caller.email || "").trim().toLowerCase();
      const { data: instr } = await svc.from("instructors")
        .select("id").eq("school_id", schoolId).eq("active", true)
        .or(`auth_user_id.eq.${caller.id},email_norm.eq.${emailNorm}`)
        .maybeSingle();
      allowed = !!instr;
    }
    if (!allowed) return json({ ok: false, error: "Not authorized for this school." }, 403);

    const nowIso = new Date().toISOString();

    let { data: thread } = await svc.from("support_threads").select("*").eq("school_id", schoolId).maybeSingle();
    if (!thread) {
      const ins = await svc.from("support_threads")
        .insert({ school_id: schoolId, status: "open", last_sender: "school", last_message_at: nowIso, unread_nmao: 1 })
        .select("*").single();
      thread = ins.data;
    } else {
      await svc.from("support_threads")
        .update({ status: "open", last_sender: "school", last_message_at: nowIso, unread_nmao: (thread.unread_nmao || 0) + 1 })
        .eq("id", thread.id);
    }
    if (!thread) return json({ ok: false, error: "Could not open a thread." }, 200);

    await svc.from("support_messages").insert({
      thread_id: thread.id, school_id: schoolId, sender: "school",
      author: school.name || "School", body: msg,
      kind: isError ? "error" : null, attachments: attachments.length ? attachments : null,
    });

    // notify the team: active specialists + primary
    const recipients = new Set<string>();
    const { data: specs } = await svc.from("onboarding_specialists").select("email").eq("active", true);
    for (const s of specs || []) if (s && s.email) recipients.add(String(s.email).trim().toLowerCase());
    for (const p of PRIMARY) recipients.add(p);

    const replyUrl = REPLY_BASE + "?t=" + thread.reply_token;
    await Promise.all([...recipients].map((to) => emailTeam(to, school.name || "", msg, replyUrl, isError, attachments)));

    // urgent errors also text the NMAO lead
    if (isError) {
      const sms = "⚠️ NMAO error report from " + (school.name || "a school") + ": " +
        msg.slice(0, 160) + (attachments.length ? " [screenshot attached]" : "") + " — reply: " + replyUrl;
      await sendAlertSms(sms);
    }

    return json({ ok: true, thread_id: thread.id }, 200);
  } catch (e) {
    console.error("support-send error:", e);
    return json({ ok: false, error: "Something went wrong sending your message." }, 200);
  }
});
