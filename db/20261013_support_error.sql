-- ===== Support desk: error reports (screenshot + description), attachments =====
alter table support_messages add column if not exists attachments text[];
alter table support_messages add column if not exists kind text;         -- null (question) | 'error'

-- public bucket for support screenshots (random filenames; images only, 10 MB cap)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('support-uploads','support-uploads', true, 10485760,
        array['image/png','image/jpeg','image/jpg','image/webp','image/gif'])
on conflict (id) do update set public=true,
  file_size_limit=excluded.file_size_limit, allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists support_uploads_insert on storage.objects;
create policy support_uploads_insert on storage.objects
  for insert to authenticated with check (bucket_id='support-uploads');
drop policy if exists support_uploads_read on storage.objects;
create policy support_uploads_read on storage.objects
  for select using (bucket_id='support-uploads');
