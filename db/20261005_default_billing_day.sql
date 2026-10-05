-- School-level default billing day (Membership DB ykiozrdwudawpxdzbbyc) — applied 2026-10-05.
-- Prevents the "signup-day becomes billing-day" trap (the one TAOSD hit): new membership plans
-- now inherit an explicit, well-defaulted school-level billing day instead of each plan silently
-- defaulting to the member's signup anniversary. See dashboard.html:
--   §BILLING-DAY-DISPLAY (smNextChargeDate) and §DEFAULT-BILLING-DAY (this feature).
--
--   default_autopay_day       — the day-of-month new plans prefill their "Autopay Billing Day" with.
--                               Values mirror the per-plan control: 'anniversary', or a day '1'..'28'.
--                               Platform default = '1' (the 1st of the month).
--   default_prorate_to_first  — whether new plans prefill "Prorate first charge to that day" on.
--   default_billing_day_set   — whether the school has made (or dismissed) the one-time onboarding
--                               ask. Backfilled TRUE for existing schools so they are never nagged;
--                               NEW schools insert FALSE (column default) and see the ask once when
--                               they create their first membership plan.

alter table public.schools
  add column if not exists default_autopay_day      text    default '1',
  add column if not exists default_prorate_to_first boolean default true,
  add column if not exists default_billing_day_set  boolean default false;

-- Backfill existing schools to the platform default and mark the one-time ask as already handled.
-- NOTE: this only sets the DEFAULT new plans inherit going forward — it does not touch any existing
-- membership plan's autopay_day / prorate_to_first.
update public.schools
   set default_autopay_day      = coalesce(default_autopay_day, '1'),
       default_prorate_to_first = coalesce(default_prorate_to_first, true),
       default_billing_day_set  = true
 where default_billing_day_set is distinct from true
    or default_autopay_day is null
    or default_prorate_to_first is null;
