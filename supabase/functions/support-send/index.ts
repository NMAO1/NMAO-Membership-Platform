// ============================================================
// EDGE FUNCTION: support-send   (Member dashboard → NMAO support desk)
// Called by: dashboard.html support chat bubble (logged-in school owner /
//            instructor, browser, CORS). Verify JWT ON.
//
// Stores the school's message in the shared support thread (one per school) and
// FANS OUT an email to the whole team — every active onboarding_specialist plus
// the primary addresses — each with a one-click tokenized reply link, so any
// specialist can pick it up and respond fast.
//
// Input:  { school_id, body }     (Authorization: Bearer <user jwt>)
// Output: { ok:true, thread_id } | { ok:false, error }
// ============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const RESEND_KEY = Deno.env.get("RESEND_OUTREACH_KEY") || "";
const FROM = "NMAO Support <outreach@outreach.nmao.us>";
const PRIMARY = ["senseibrad@nmao.us", "support@nmao.us"]; // always notified
const REPLY_BASE = "https://app.nmao.us/support-reply.html";

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

async function emailTeam(to: string, schoolName: string, msg: string, replyUrl: string): Promise<boolean> {
  if (!RESEND_KEY || !to) return false;
  const safeUrl = esc(replyUrl);
  const html =
    '<div style="font-family:Georgia,serif;color:#1a1a1a;line-height:1.6;max-width:580px">' +
    '<p style="font-size:0.8rem;letter-spacing:0.12em;text-transform:uppercase;color:#B8862C;margin:0 0 0.3rem">New support question</p>' +
    "<p><strong>" + esc(schoolName || "A school") + "</strong> sent a message to NMAO support:</p>" +
    '<blockquote style="margin:0.6rem 0;padding:0.75rem 1rem;background:#f6f3ec;border-left:3px solid #B8862C;white-space:pre-wrap">' +
    esc(msg) + "</blockquote>" +
    '<p><a href="' + safeUrl + '" style="display:inline-block;background:#B8862C;color:#fff;' +
    'padding:0.7rem 1.2rem;text-decoration:none;border-radius:4px;font-weight:bold">Open & reply</a></p>' +
    '<p style="font-size:0.82rem;color:#555">The first teammate to reply claims the thread, so we never double up or miss one. ' +
    "Your reply appears in the school's dashboard right away.</p>" +
    '<p style="font-size:0.82rem;color:#555">Or paste this link:<br/>' + safeUrl + "</p>" +
    "<p>— NMAO Support Desk</p></div>";
  try {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": "Bearer " + RESEND_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: FROM, to, reply_to: "support@nmao.us",
        subject: "Support question — " + (schoolName || "a school"), html,
      }),
    });
    const rj = await r.json().catch(() => ({}));
    return !!(r.ok && rj && rj.id);
  } catch (e) {
    console.error("emailTeam failed:", e);
    return false;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  try {
    // --- identify the caller from their JWT ---
    const authHeader = req.headers.get("Authorization") || "";
    const authClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } } });
    const { data: userData } = await authClient.auth.getUser();
    const caller = userData && userData.user;
    if (!caller) return json({ ok: false, error: "Not signed in." }, 401);

    const body = await req.json().catch(() => ({}));
    const schoolId = String(body.school_id || "").trim();
    const msg = String(body.body || "").trim();
    if (!schoolId) return json({ ok: false, error: "Missing school." }, 200);
    if (!msg) return json({ ok: false, error: "Your message is empty." }, 200);
    if (msg.length > 4000) return json({ ok: false, error: "Message is too long (max 4000 characters)." }, 200);

    // --- verify the caller owns or instructs this school ---
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

    // --- upsert the school's thread ---
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

    // --- store the message ---
    await svc.from("support_messages").insert({
      thread_id: thread.id, school_id: schoolId, sender: "school",
      author: school.name || "School", body: msg,
    });

    // --- notify the team: every active specialist + primary ---
    const recipients = new Set<string>();
    const { data: specs } = await svc.from("onboarding_specialists").select("email").eq("active", true);
    for (const s of specs || []) if (s && s.email) recipients.add(String(s.email).trim().toLowerCase());
    for (const p of PRIMARY) recipients.add(p);

    const replyUrl = REPLY_BASE + "?t=" + thread.reply_token;
    await Promise.all([...recipients].map((to) => emailTeam(to, school.name || "", msg, replyUrl)));

    return json({ ok: true, thread_id: thread.id }, 200);
  } catch (e) {
    console.error("support-send error:", e);
    return json({ ok: false, error: "Something went wrong sending your message." }, 200);
  }
});
