-- Closed-loop attribution (Membership DB ykiozrdwudawpxdzbbyc) — applied 2026-09-28.
-- Links the enrolled student back to the lead it came from so ad/organic campaigns
-- can be measured all the way to enrollment revenue (LTV). Drives the "Campaign
-- Attribution & ROI" panel on the Leads page in dashboard.html.

alter table public.students add column if not exists lead_id uuid references public.leads(id) on delete set null;
create index if not exists students_lead_id_idx on public.students(lead_id) where lead_id is not null;

-- Per-channel / per-campaign funnel + revenue for one school over a date window.
-- SECURITY INVOKER (default): RLS on leads/students/payments scopes rows to the caller's school.
create or replace function public.lead_attribution_rollup(
  p_school_id uuid,
  p_from timestamptz default (now() - interval '90 days'),
  p_to   timestamptz default now()
) returns table (
  channel text, campaign text, leads integer, trials integer,
  converted integer, enrolled integer, revenue numeric
) language sql stable as $fn$
  select
    coalesce(nullif(l.utm_source,''), nullif(l.source,''), '(none)')          as channel,
    coalesce(nullif(l.utm_campaign,''), '')                                   as campaign,
    count(distinct l.id)::int                                                 as leads,
    count(distinct l.id) filter (where l.trial_redeemed_at is not null)::int  as trials,
    count(distinct l.id) filter (where l.converted_at is not null)::int       as converted,
    count(distinct s.id)::int                                                 as enrolled,
    coalesce(sum(rev.amt), 0)::numeric                                        as revenue
  from public.leads l
  left join public.students s on s.lead_id = l.id
  left join lateral (
    select sum(coalesce(p.net_amount, p.amount) - coalesce(p.amount_refunded_cents,0)/100.0) as amt
    from public.payments p
    where p.student_id = s.id and p.status = 'paid'
  ) rev on true
  where l.school_id = p_school_id and l.deleted_at is null
    and l.created_at >= p_from and l.created_at < p_to
  group by 1, 2
  order by revenue desc, leads desc;
$fn$;
grant execute on function public.lead_attribution_rollup(uuid, timestamptz, timestamptz) to authenticated;
