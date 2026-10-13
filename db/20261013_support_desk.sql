-- ============================================================
-- SUPPORT DESK — schools ↔ NMAO support chat
-- One thread per school. Schools message from the dashboard chat bubble;
-- the NMAO team (onboarding_specialists + primary) is notified and replies
-- via a tokenized reply page. Full queryable record of every conversation.
-- Additive only — safe on the live DB.
-- ============================================================

create table if not exists support_threads (
  id              uuid primary key default gen_random_uuid(),
  school_id       uuid not null references schools(id) on delete cascade,
  status          text not null default 'open',          -- 'open' | 'resolved'
  assigned_to     text,                                  -- specialist who claimed (name/email)
  assigned_at     timestamptz,
  reply_token     uuid not null default gen_random_uuid(),-- in the team's reply link
  last_message_at timestamptz not null default now(),
  last_sender     text,                                  -- 'school' | 'nmao'
  unread_school   integer not null default 0,            -- unseen NMAO replies, for the school
  unread_nmao     integer not null default 0,            -- unseen school messages, for the team
  created_at      timestamptz not null default now(),
  unique (school_id)
);

create table if not exists support_messages (
  id         uuid primary key default gen_random_uuid(),
  thread_id  uuid not null references support_threads(id) on delete cascade,
  school_id  uuid not null references schools(id) on delete cascade,
  sender     text not null check (sender in ('school','nmao')),
  author     text,                                       -- display name of the sender
  body       text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_support_messages_thread on support_messages(thread_id, created_at);
create index if not exists idx_support_messages_school on support_messages(school_id, created_at);
create index if not exists idx_support_threads_school  on support_threads(school_id);

-- A caller may access a school's support if they own it or are an active instructor.
create or replace function public.can_access_school_support(p_school uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
           select 1 from schools s
            where s.id = p_school and s.owner_id = auth.uid()
         )
      or exists (
           select 1 from instructors i
            where i.school_id = p_school
              and coalesce(i.active, true)
              and ( i.auth_user_id = auth.uid()
                    or i.email_norm = lower(coalesce(auth.jwt() ->> 'email', '')) )
         );
$$;

alter table support_threads  enable row level security;
alter table support_messages enable row level security;

-- Schools (owner/instructor) may READ their own thread + messages (for the
-- dashboard chat + realtime). All writes go through the Edge Functions
-- (service role), so there are intentionally no anon/user INSERT/UPDATE policies.
drop policy if exists support_threads_sel on support_threads;
create policy support_threads_sel on support_threads
  for select using (public.can_access_school_support(school_id));

drop policy if exists support_messages_sel on support_messages;
create policy support_messages_sel on support_messages
  for select using (public.can_access_school_support(school_id));

-- Realtime so the dashboard sees NMAO replies live.
alter table support_messages replica identity full;
alter table support_threads  replica identity full;
do $$
begin
  begin execute 'alter publication supabase_realtime add table support_messages'; exception when others then null; end;
  begin execute 'alter publication supabase_realtime add table support_threads';  exception when others then null; end;
end $$;
