// ============================================================
// EDGE FUNCTION: onboarding-admin   (NMAO Onboarding ‚Äî Admin tool)
// Called by: specialist.html (logged-in admin, browser, CORS)
// JWT: leave Verify JWT ON -- this requires an authenticated caller, and the
//      function additionally checks that the caller is an ONBOARDING ADMIN.
//      (Unlike the public funnel EFs, which are JWT-off + anon.)
//
// Privileged roster actions that need the service role (creating an auth user
// cannot be done from the browser). Currently: create_specialist.
//
//   create_specialist: invites a new teammate (Supabase emails them a link to
//   set their password), then inserts their onboarding_specialists row linked
//   to the new auth user, seeded with Mon-Fri 9-5 availability so they are
//   ready to take calls once active. They can refine hours in specialist.html.
//
// Input:  { action:'create_specialist', name, email, phone?, timezone? }
// Output: { ok:true, specialist_id } | { ok:false, error }
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const ADMIN_URL = Deno.env.get("ONBOARDING_ADMIN_URL") || "https://onboard.nmao.us/specialist.html";
const DEFAULT_TZ = "America/New_York";

const svc = createClient(SUPABASE_URL, SERVICE_KEY);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  try {
    // --- Identify caller from their JWT, then confirm they are an admin ---
    const authHeader = req.headers.get("Authorization") || "";
    const authClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } } });
    const { data: userData } = await authClient.auth.getUser();
    const caller = userData && userData.user;
    if (!caller) return json({ ok: false, error: "Not signed in." }, 401);

    const { data: me } = await svc.from("onboarding_specialists")
      .select("is_admin").eq("user_id", caller.id).single();
    if (!me || me.is_admin !== true) return json({ ok: false, error: "Admins only." }, 403);

    const body = await req.json().catch(() => ({}));
    const action = String(body.action || "");

    if (action === "create_specialist") {
      const name = String(body.name || "").trim();
      const email = String(body.email || "").trim().toLowerCase();
      const phone = String(body.phone || "").trim();
      const timezone = String(body.timezone || DEFAULT_TZ).trim() || DEFAULT_TZ;
      if (!name) return json({ ok: false, error: "Name is required." }, 200);
      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ ok: false, error: "A valid email is required." }, 200);

      // Already a specialist with this email?
      const { data: dupe } = await svc.from("onboarding_specialists").select("id").eq("email", email).maybeSingle();
      if (dupe) return json({ ok: false, error: "A specialist with that email already exists." }, 200);

      // Invite the new teammate (creates the auth user + emails a set-password link).
      const { data: inv, error: invErr } = await svc.auth.admin.inviteUserByEmail(email, { redirectTo: ADMIN_URL });
      if (invErr || !inv || !inv.user) {
        return json({ ok: false, error: (invErr && invErr.message) || "Could not send the invite." }, 200);
      }

      // Create their specialist row linked to the new auth user.
      const { data: spec, error: specErr } = await svc.from("onboarding_specialists").insert({
        user_id: inv.user.id,
        name: name,
        email: email,
        phone: phone || null,
        timezone: timezone,
        active: true,
        is_admin: false,
      }).select("id").single();
      if (specErr || !spec) {
        return json({ ok: false, error: (specErr && specErr.message) || "Could not create the specialist." }, 200);
      }

      // Seed Mon-Fri 9-5 default availability.
      const rows = [1, 2, 3, 4, 5].map((d) => ({
        specialist_id: spec.id, day_of_week: d, start_time: "09:00", end_time: "17:00",
      }));
      await svc.from("onboarding_availability").insert(rows);

      return json({ ok: true, specialist_id: spec.id }, 200);
    }

    // Waive/unwaive a school's $99/mo platform subscription by flipping its
    // accreditation. The prospect must be linked to a live member school. We hold
    // the service role, so we proxy to the service-role-gated set-school-accreditation.
    if (action === "set_accreditation") {
      const prospectId = String(body.prospect_id || "");
      const accredited = body.accredited === true;
      if (!prospectId) return json({ ok: false, error: "prospect_id is required." }, 200);
      const { data: pros } = await svc.from("prospect_schools")
        .select("member_school_id, school_name").eq("id", prospectId).single();
      if (!pros) return json({ ok: false, error: "Prospect not found." }, 200);
      if (!(pros as any).member_school_id) {
        return json({ ok: false, error: "This school isn't linked to a live member account yet ‚Äî it links automatically once they sign up on the platform." }, 200);
      }
      const r = await fetch(SUPABASE_URL + "/functions/v1/set-school-accreditation", {
        method: "POST",
        headers: { Authorization: "Bearer " + SERVICE_KEY, "Content-Type": "application/json" },
        body: JSON.stringify({ school_id: (pros as any).member_school_id, accredited }),
      });
      const d = await r.json().catch(() => ({}));
      if (!r.ok || (d && d.error)) return json({ ok: false, error: (d && d.error) || "Could not update accreditation." }, 200);
      // Reflect it on the prospect record too, so the specialist view stays in sync.
      // NOTE: prospect_schools has NO `accredited` column (only accreditation_status
      // + accredited_at). Writing it errored silently and the whole update was lost,
      // so the specialist view never reflected a waiver. Write only real columns and
      // surface a warning if the sync itself fails (the waiver above already applied).
      const { error: syncErr } = await svc.from("prospect_schools").update({
        accreditation_status: accredited ? "accredited" : "in_progress",
        accredited_at: accredited ? new Date().toISOString() : null,
      }).eq("id", prospectId);
      if (syncErr) console.error("prospect_schools accreditation sync failed:", prospectId, syncErr.message);
      return json({ ok: true, accredited, school: (pros as any).school_name, subscription: d.subscription, sync_warning: syncErr ? syncErr.message : undefined }, 200);
    }

    return json({ ok: false, error: "Unknown action." }, 200);
  } catch (e) {
    console.error("onboarding-admin error:", e);
    return json({ ok: false, error: (e && (e as any).message) || "Failed" }, 200);
  }
});