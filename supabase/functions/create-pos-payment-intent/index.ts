// =====================================================================
// create-pos-payment-intent — one-time keyed-card POS charge
// =====================================================================
// Creates a card PaymentIntent on the school's CONNECTED Stripe account
// (direct charge) so a staff member can key in a new card at the POS —
// e.g. a guest / company-issued virtual card that can't use a hosted link.
// The card PAN is entered client-side via Stripe Elements and confirmed in
// the browser; it never touches this function or our database.
//
// Returns: { client_secret, payment_intent_id, account_id, publishable_key }
//
// Required env (Supabase → Edge Functions → Secrets):
//   SUPABASE_URL, SUPABASE_ANON_KEY   (to authorize the caller under RLS)
//   STRIPE_SECRET_KEY                 (platform secret key; acts on the
//                                      connected account via stripeAccount)
//   STRIPE_PUBLISHABLE_KEY            (platform publishable key; returned to
//                                      the client for Elements)
//
// Deploy:  supabase functions deploy create-pos-payment-intent
//
// Note on keyed/MOTO charges: by default this processes as a standard online
// card payment (works for most virtual-card numbers). If your processor
// requires MOTO for keyed entry, pass { moto: true } and ensure the connected
// account is approved for MOTO in Stripe.
// =====================================================================

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'jsr:@supabase/supabase-js@2';
import Stripe from 'npm:stripe@14';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405);

  try {
    const authHeader = req.headers.get('Authorization') || '';
    const body = await req.json().catch(() => ({}));
    const { school_id, line_items, student_id, description, moto } = body as {
      school_id?: string;
      line_items?: Array<{ unit_amount?: number; quantity?: number }>;
      student_id?: string | null;
      description?: string;
      moto?: boolean;
    };

    if (!school_id || !Array.isArray(line_items) || line_items.length === 0) {
      return json({ error: 'school_id and line_items are required' }, 400);
    }

    // Server-authoritative amount (never trust a client-sent total).
    let amount = 0;
    for (const li of line_items) {
      amount += Math.round(Number(li.unit_amount) || 0) * (Number(li.quantity) || 1);
    }
    if (amount <= 0) return json({ error: 'Amount must be greater than zero' }, 400);

    // Authorize: read the school row using the CALLER's JWT so RLS confirms
    // they are staff/owner of this school. If they can't read it, they can't charge.
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: school, error: schoolErr } = await userClient
      .from('schools')
      .select('id, stripe_connect_account_id')
      .eq('id', school_id)
      .single();
    if (schoolErr || !school) return json({ error: 'Not authorized for this school' }, 403);
    if (!school.stripe_connect_account_id) return json({ error: 'This school has not connected Stripe yet.' }, 400);

    const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, { apiVersion: '2024-06-20' });

    const pi = await stripe.paymentIntents.create(
      {
        amount,
        currency: 'usd',
        description: description || 'POS sale',
        metadata: {
          school_id,
          student_id: student_id || '',
          source: 'pos_new_card',
          line_items: JSON.stringify(line_items).slice(0, 4500),
        },
        payment_method_types: ['card'],
        ...(moto ? { payment_method_options: { card: { moto: true } } } : {}),
      },
      { stripeAccount: school.stripe_connect_account_id },
    );

    return json({
      client_secret: pi.client_secret,
      payment_intent_id: pi.id,
      account_id: school.stripe_connect_account_id,
      publishable_key: Deno.env.get('STRIPE_PUBLISHABLE_KEY'),
    });
  } catch (e: any) {
    return json({ error: (e && e.message) || 'Server error' }, 500);
  }
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
