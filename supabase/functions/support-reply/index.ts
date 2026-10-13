// ============================================================
// EDGE FUNCTION: support-reply   (NMAO team → school, via tokenized link)
// Called by: support-reply.html (opened from the fan-out email; no login).
// Verify JWT OFF — the per-thread reply_token in the link is the authorization.
//
//   GET  ?t=<reply_token>                        -> load thread + messages
//   POST { t, action:'reply', body, agent }      -> post a reply (auto-claims)
//   POST { t, action:'claim',  agent }           -> claim the thread
//   POST { t, action:'resolve' }                 -> mark resolved
//
// First reply auto-claims so the team never double-answers or drops a question.
// ============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_KEY = Deno.env.get("RESEND_OUTREACH_KEY") || "";
const FROM = "NMAO Support <outreach@outreach.nmao.us>";
const DASH_URL = "https://app.nmao.us/dashboard.html";

// Attachments on a team reply may only be curated guide screenshots (served
// from our own site) or files already in our public upload bucket — never an
// arbitrary external URL.
const ALLOWED_SHOT_PREFIXES = [
  "https://app.nmao.us/help-shots/",
  SUPABASE_URL + "/storage/v1/object/public/support-uploads/",
];
function cleanAttachments(input: unknown): string[] {
  if (!Array.isArray(input)) return [];
  return input
    .map((a) => String(a || ""))
    .filter((u) => ALLOWED_SHOT_PREFIXES.some((p) => u.startsWith(p)))
    .slice(0, 6);
}

const svc = createClient(SUPABASE_URL, SERVICE_KEY);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
function esc(s: string): string {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function emailSchool(to: string, schoolName: string, msg: string, shots: string[] = []): Promise<boolean> {
  if (!RESEND_KEY || !to) return false;
  const shotsHtml = (shots || []).map((u) =>
    '<a href="' + esc(u) + '"><img src="' + esc(u) + '" alt="screenshot" style="max-width:100%;border:1px solid #ccc;border-radius:8px;margin:0.5rem 0"/></a>').join("");
  const html =
    '<div style="font-family:Georgia,serif;color:#1a1a1a;line-height:1.6;max-width:560px">' +
    "<p>Hi" + (schoolName ? " " + esc(schoolName) : "") + ",</p>" +
    "<p>The NMAO team replied to your support question:</p>" +
    '<blockquote style="margin:0.6rem 0;padding:0.75rem 1rem;background:#f6f3ec;border-left:3px solid #B8862C;white-space:pre-wrap">' +
    esc(msg) + "</blockquote>" +
    shotsHtml +
    '<p><a href="' + esc(DASH_URL) + '" style="display:inline-block;background:#B8862C;color:#fff;' +
    'padding:0.7rem 1.2rem;text-decoration:none;border-radius:4px;font-weight:bold">Open your dashboard</a></p>' +
    '<p style="font-size:0.82rem;color:#555">You can reply right from the support chat in your dashboard.</p>' +
    "<p>— The NMAO Team</p></div>";
  try {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": "Bearer " + RESEND_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({ from: FROM, to, reply_to: "support@nmao.us", subject: "NMAO replied to your question", html }),
    });
    const rj = await r.json().catch(() => ({}));
    return !!(r.ok && rj && rj.id);
  } catch (_e) {
    return false;
  }
}

async function loadThread(token: string) {
  if (!UUID_RE.test(token)) return null;
  const { data: thread } = await svc.from("support_threads").select("*").eq("reply_token", token).maybeSingle();
  return thread || null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = new URL(req.url);

    if (req.method === "GET") {
      const token = (url.searchParams.get("t") || "").trim();
      const thread = await loadThread(token);
      if (!thread) return json({ ok: false, error: "This reply link is invalid or has expired." }, 200);
      const { data: school } = await svc.from("schools").select("name,email").eq("id", thread.school_id).maybeSingle();
      const { data: msgs } = await svc.from("support_messages")
        .select("sender,author,body,created_at,attachments,kind").eq("thread_id", thread.id).order("created_at", { ascending: true });
      // opening the thread clears the team's unread counter
      await svc.from("support_threads").update({ unread_nmao: 0 }).eq("id", thread.id);
      return json({
        ok: true,
        school: (school && school.name) || "School",
        status: thread.status,
        assigned_to: thread.assigned_to || null,
        messages: msgs || [],
      }, 200);
    }

    if (req.method === "POST") {
      const b = await req.json().catch(() => ({}));
      const token = String(b.t || "").trim();
      const action = String(b.action || "reply");
      const agent = (String(b.agent || "").trim() || "NMAO Team").slice(0, 80);
      const thread = await loadThread(token);
      if (!thread) return json({ ok: false, error: "This reply link is invalid or has expired." }, 200);
      const nowIso = new Date().toISOString();

      if (action === "claim") {
        await svc.from("support_threads").update({ assigned_to: agent, assigned_at: nowIso }).eq("id", thread.id);
        return json({ ok: true, assigned_to: agent }, 200);
      }
      if (action === "resolve") {
        await svc.from("support_threads").update({ status: "resolved" }).eq("id", thread.id);
        return json({ ok: true, status: "resolved" }, 200);
      }

      // reply
      const msg = String(b.body || "").trim();
      if (!msg) return json({ ok: false, error: "Your reply is empty." }, 200);
      if (msg.length > 4000) return json({ ok: false, error: "Reply is too long (max 4000 characters)." }, 200);
      const attachments = cleanAttachments(b.attachments);

      await svc.from("support_messages").insert({
        thread_id: thread.id, school_id: thread.school_id, sender: "nmao", author: agent, body: msg,
        attachments: attachments.length ? attachments : null,
      });
      const upd: Record<string, unknown> = {
        status: "open", last_sender: "nmao", last_message_at: nowIso,
        unread_school: (thread.unread_school || 0) + 1,
      };
      if (!thread.assigned_to) { upd.assigned_to = agent; upd.assigned_at = nowIso; } // first reply claims it
      await svc.from("support_threads").update(upd).eq("id", thread.id);

      const { data: school } = await svc.from("schools").select("name,email").eq("id", thread.school_id).maybeSingle();
      if (school && school.email) await emailSchool(school.email, school.name || "", msg, attachments);

      return json({ ok: true, assigned_to: upd.assigned_to || thread.assigned_to }, 200);
    }

    return json({ ok: false, error: "method_not_allowed" }, 405);
  } catch (e) {
    console.error("support-reply error:", e);
    return json({ ok: false, error: "Something went wrong." }, 200);
  }
});
