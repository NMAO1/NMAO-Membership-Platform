// get-school-onboarding-docs — owner-gated read of a school's onboarding documents.
//
// The documents a school uploads during onboarding live on the PROSPECT pipeline
// (prospect_schools + prospect_documents + the private onboarding-uploads bucket), which is
// otherwise admin-only. This lets the authenticated SCHOOL OWNER see their own docs in the
// member dashboard: it resolves the prospect via prospect_schools.member_school_id = school_id,
// lists its prospect_documents, and returns short-lived signed download URLs. Read-only.
//
// JWT: ON (needs the owner's session). Additionally verifies the caller owns the school.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const BUCKET = 'onboarding-uploads'
const SIGN_TTL = 3600 // 1 hour

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

// The caller must be the signed-in owner of this school (the anon key resolves to no user → rejected).
async function requireOwner(req: Request, sb: any, school_id: string): Promise<boolean> {
  const bearer = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '')
  let uid: string | null = null
  try {
    const ua = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: 'Bearer ' + bearer } },
    })
    const { data } = await ua.auth.getUser(); uid = data?.user?.id || null
  } catch (_e) { uid = null }
  if (!uid) return false
  const { data: owner } = await sb.from('schools').select('id').eq('id', school_id).eq('owner_id', uid).maybeSingle()
  return !!owner
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const { school_id } = await req.json()
    if (!school_id) return json({ ok: false, error: 'school_id required' }, 400)

    const svc = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    if (!(await requireOwner(req, svc, school_id))) {
      return json({ ok: false, error: 'Only the school owner can view onboarding documents.' }, 403)
    }

    // Resolve the prospect linked to this member school.
    const { data: prospect } = await svc.from('prospect_schools')
      .select('id, accreditation_status').eq('member_school_id', school_id).maybeSingle()
    if (!prospect) return json({ ok: true, docs: [], accreditation_status: null })

    const { data: rows } = await svc.from('prospect_documents')
      .select('id, category, original_name, file_path, content_type, size_bytes, status, uploaded_at')
      .eq('prospect_id', prospect.id).order('uploaded_at', { ascending: true })

    const docs = []
    for (const d of (rows || [])) {
      let url: string | null = null
      try {
        const { data: s } = await svc.storage.from(BUCKET).createSignedUrl(d.file_path, SIGN_TTL)
        url = s?.signedUrl || null
      } catch (_e) { url = null }
      docs.push({
        id: d.id, category: d.category, original_name: d.original_name,
        content_type: d.content_type, size_bytes: d.size_bytes, status: d.status,
        uploaded_at: d.uploaded_at, url,
      })
    }
    return json({ ok: true, docs, accreditation_status: prospect.accreditation_status })
  } catch (e) {
    return json({ ok: false, error: String((e as any)?.message || e) }, 500)
  }
})
