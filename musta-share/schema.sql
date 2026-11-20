-- Musta-SHARE | مستشار — Supabase schema (PostgreSQL + pgvector + RLS)
create extension if not exists vector;
create extension if not exists pg_trgm;

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text, full_name text, avatar_url text,
  role text not null default 'student' check (role in ('student','supervisor','admin')),
  created_at timestamptz default now());
create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  name text not null, description text, created_at timestamptz default now());
create table public.workspace_members (
  workspace_id uuid references public.workspaces(id) on delete cascade,
  user_id uuid references public.users(id) on delete cascade,
  primary key (workspace_id, user_id));
create table public.documents (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid references public.workspaces(id) on delete cascade, -- null = official regulatory corpus
  uploaded_by uuid references public.users(id),
  file_name text not null, file_path text, file_size bigint, page_count int,
  is_official boolean default false,
  processing_status text not null default 'uploading'
    check (processing_status in ('uploading','processing','indexed','failed')),
  created_at timestamptz default now());
create table public.document_chunks (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete cascade,
  chunk_index int not null, content text not null, page_number int,
  embedding vector(1024), metadata jsonb default '{}',
  fts tsvector generated always as (to_tsvector('simple', content)) stored);
create index on public.document_chunks using hnsw (embedding vector_cosine_ops);
create index on public.document_chunks using gin (fts);
create index on public.document_chunks using gin (content gin_trgm_ops);
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  workspace_id uuid references public.workspaces(id) on delete set null,
  title text, created_at timestamptz default now());
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  role text not null check (role in ('user','assistant')),
  content text not null, language text, created_at timestamptz default now());
create table public.message_sources (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  document_id uuid references public.documents(id),
  page_number int, relevance_score real, quoted_text text);

-- Row Level Security
alter table public.users enable row level security;
alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.documents enable row level security;
alter table public.document_chunks enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.message_sources enable row level security;

create or replace function public.is_member(ws uuid) returns boolean
language sql security definer stable as $$
  select exists(select 1 from public.workspaces w where w.id = ws and w.owner_id = auth.uid())
      or exists(select 1 from public.workspace_members m where m.workspace_id = ws and m.user_id = auth.uid()) $$;

create policy users_self on public.users for all using (id = auth.uid()) with check (id = auth.uid());
create policy ws_owner on public.workspaces for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy ws_member_read on public.workspaces for select using (public.is_member(id));
create policy wsm_owner on public.workspace_members for all
  using (exists(select 1 from public.workspaces w where w.id = workspace_id and w.owner_id = auth.uid()));
create policy docs_read on public.documents for select
  using (is_official or (workspace_id is not null and public.is_member(workspace_id)));
create policy docs_write on public.documents for all
  using (workspace_id is not null and public.is_member(workspace_id))
  with check (workspace_id is not null and public.is_member(workspace_id));
create policy chunks_read on public.document_chunks for select
  using (exists(select 1 from public.documents d where d.id = document_id
        and (d.is_official or (d.workspace_id is not null and public.is_member(d.workspace_id)))));
create policy conv_own on public.conversations for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy msg_own on public.messages for all
  using (exists(select 1 from public.conversations c where c.id = conversation_id and c.user_id = auth.uid()))
  with check (exists(select 1 from public.conversations c where c.id = conversation_id and c.user_id = auth.uid()));
create policy src_own on public.message_sources for all
  using (exists(select 1 from public.messages m join public.conversations c on c.id = m.conversation_id
        where m.id = message_id and c.user_id = auth.uid()));
-- Official corpus (is_official = true) is written only with the service-role key (ingestion script).

-- Hybrid search: vector similarity + full-text, merged by reciprocal rank fusion
create or replace function public.match_chunks(query_embedding vector(1024), query_text text,
                                               ws uuid default null, k int default 6)
returns table (id uuid, document_id uuid, file_name text, page_number int, content text, score real)
language sql stable as $$
  with v as (
    select c.id, row_number() over (order by c.embedding <=> query_embedding) r
    from public.document_chunks c join public.documents d on d.id = c.document_id
    where d.is_official or d.workspace_id = ws order by c.embedding <=> query_embedding limit 20),
  f as (
    select c.id, row_number() over (order by ts_rank(c.fts, plainto_tsquery('simple', query_text)) desc) r
    from public.document_chunks c join public.documents d on d.id = c.document_id
    where (d.is_official or d.workspace_id = ws) and c.fts @@ plainto_tsquery('simple', query_text) limit 20)
  select c.id, c.document_id, d.file_name, c.page_number, c.content,
         (coalesce(1.0/(60+v.r),0) + coalesce(1.0/(60+f.r),0))::real as score
  from public.document_chunks c join public.documents d on d.id = c.document_id
  left join v on v.id = c.id left join f on f.id = c.id
  where v.id is not null or f.id is not null order by score desc limit k $$;
