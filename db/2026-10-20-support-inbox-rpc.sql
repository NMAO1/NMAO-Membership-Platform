-- Team Support inbox: all threads with school name + latest-message preview.
-- Gated to ACTIVE onboarding_specialists (everyone on the team, not just admins).
create or replace function public.support_inbox_threads()
returns table(
  thread_id uuid, school_id uuid, school_name text, status text,
  assigned_to text, unread_nmao int, last_message_at timestamptz,
  last_sender text, reply_token uuid, last_body text, last_kind text
)
language sql stable security definer set search_path to 'public'
as $$
  select t.id, t.school_id, s.name, t.status, t.assigned_to, t.unread_nmao,
         t.last_message_at, t.last_sender, t.reply_token, lm.body, lm.kind
  from support_threads t
  left join schools s on s.id = t.school_id
  left join lateral (
    select m.body, m.kind from support_messages m
    where m.thread_id = t.id order by m.created_at desc limit 1
  ) lm on true
  where exists (select 1 from onboarding_specialists o where o.user_id = auth.uid() and o.active)
  order by (t.status='open') desc, t.last_message_at desc nulls last;
$$;
grant execute on function public.support_inbox_threads() to authenticated;
