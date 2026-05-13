-- ============================================================
-- LUCREX — Schema Supabase
-- Rulează în SQL Editor din Supabase Dashboard
-- ============================================================

-- Extensie pentru geolocație
create extension if not exists postgis;

-- ─── ENUM TYPES ─────────────────────────────────────────────
create type user_role as enum ('client', 'meserias', 'both');
create type subscription_tier as enum ('free', 'mediu', 'pro');
create type job_status as enum ('open', 'in_progress', 'completed', 'cancelled');
create type bid_status as enum ('pending', 'accepted', 'rejected');
create type sos_status as enum ('active', 'claimed', 'resolved');
create type post_type as enum ('work_done', 'question', 'availability');

-- ─── 1. USERS ───────────────────────────────────────────────
-- Extinde tabelul auth.users al Supabase cu date extra
create table public.users (
  id            uuid primary key references auth.users(id) on delete cascade,
  phone         text unique,
  full_name     text,
  role          user_role not null default 'client',
  avatar_url    text,
  city          text,
  neighborhood  text,
  lat           float8,
  lng           float8,
  created_at    timestamptz not null default now()
);

-- Activează RLS (Row Level Security)
alter table public.users enable row level security;

-- Politici RLS: fiecare user își vede și editează doar propriul rând
create policy "Users can view own profile"
  on public.users for select
  using (auth.uid() = id);

create policy "Users can update own profile"
  on public.users for update
  using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.users for insert
  with check (auth.uid() = id);

-- ─── 2. MESERIAS PROFILES ───────────────────────────────────
create table public.meserias_profiles (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references public.users(id) on delete cascade,
  category              text[] not null default '{}',
  bio                   text,
  subscription_tier     subscription_tier not null default 'free',
  bids_used_this_month  int2 not null default 0,
  rating_avg            float4 not null default 0,
  rating_count          int4 not null default 0,
  is_available          bool not null default true,
  is_on_duty            bool not null default false,
  promoted_until        timestamptz,
  created_at            timestamptz not null default now(),
  unique(user_id)
);

alter table public.meserias_profiles enable row level security;

create policy "Anyone can view meserias profiles"
  on public.meserias_profiles for select
  using (true);

create policy "Meserias can update own profile"
  on public.meserias_profiles for update
  using (auth.uid() = user_id);

create policy "Meserias can insert own profile"
  on public.meserias_profiles for insert
  with check (auth.uid() = user_id);

-- ─── 3. JOB REQUESTS ────────────────────────────────────────
create table public.job_requests (
  id              uuid primary key default gen_random_uuid(),
  client_id       uuid not null references public.users(id) on delete cascade,
  title           text not null,
  description     text,
  category        text not null,
  budget_min      int4,
  budget_max      int4,
  lat             float8,
  lng             float8,
  neighborhood    text,
  status          job_status not null default 'open',
  is_urgent       bool not null default false,
  accepted_bid_id uuid, -- FK adăugat mai jos după tabelul bids
  expires_at      timestamptz default (now() + interval '7 days'),
  created_at      timestamptz not null default now()
);

alter table public.job_requests enable row level security;

create policy "Anyone can view open jobs"
  on public.job_requests for select
  using (true);

create policy "Clients can insert jobs"
  on public.job_requests for insert
  with check (auth.uid() = client_id);

create policy "Clients can update own jobs"
  on public.job_requests for update
  using (auth.uid() = client_id);

-- ─── 4. BIDS ────────────────────────────────────────────────
create table public.bids (
  id              uuid primary key default gen_random_uuid(),
  job_id          uuid not null references public.job_requests(id) on delete cascade,
  meserias_id     uuid not null references public.users(id) on delete cascade,
  price           int4 not null,
  message         text,
  available_date  date,
  status          bid_status not null default 'pending',
  created_at      timestamptz not null default now(),
  unique(job_id, meserias_id) -- un meseriaș poate licita o singură dată per job
);

alter table public.bids enable row level security;

create policy "Anyone can view bids"
  on public.bids for select
  using (true);

create policy "Meserias can insert bids"
  on public.bids for insert
  with check (auth.uid() = meserias_id);

create policy "Meserias can update own bids"
  on public.bids for update
  using (auth.uid() = meserias_id);

-- Acum adăugăm FK-ul circular
alter table public.job_requests
  add constraint fk_accepted_bid
  foreign key (accepted_bid_id)
  references public.bids(id)
  on delete set null;

-- ─── 5. SOS ALERTS ──────────────────────────────────────────
create table public.sos_alerts (
  id           uuid primary key default gen_random_uuid(),
  client_id    uuid not null references public.users(id) on delete cascade,
  category     text not null,
  description  text,
  lat          float8 not null,
  lng          float8 not null,
  neighborhood text,
  status       sos_status not null default 'active',
  accepted_by  uuid references public.users(id) on delete set null,
  created_at   timestamptz not null default now()
);

alter table public.sos_alerts enable row level security;

create policy "Anyone can view active SOS"
  on public.sos_alerts for select
  using (true);

create policy "Clients can insert SOS"
  on public.sos_alerts for insert
  with check (auth.uid() = client_id);

create policy "Meserias can update SOS status"
  on public.sos_alerts for update
  using (auth.uid() = accepted_by or auth.uid() = client_id);

-- ─── 6. REVIEWS ─────────────────────────────────────────────
create table public.reviews (
  id           uuid primary key default gen_random_uuid(),
  job_id       uuid not null references public.job_requests(id) on delete cascade,
  reviewer_id  uuid not null references public.users(id) on delete cascade,
  meserias_id  uuid not null references public.users(id) on delete cascade,
  rating       int2 not null check (rating >= 1 and rating <= 5),
  would_rehire bool not null default true,
  comment      text,
  created_at   timestamptz not null default now(),
  unique(job_id, reviewer_id)
);

alter table public.reviews enable row level security;

create policy "Anyone can view reviews"
  on public.reviews for select
  using (true);

create policy "Clients can insert reviews"
  on public.reviews for insert
  with check (auth.uid() = reviewer_id);

-- ─── 7. FEED POSTS ──────────────────────────────────────────
create table public.feed_posts (
  id           uuid primary key default gen_random_uuid(),
  author_id    uuid not null references public.users(id) on delete cascade,
  type         post_type not null default 'work_done',
  body         text,
  media_urls   text[] default '{}',
  neighborhood text,
  likes_count  int4 not null default 0,
  job_id       uuid references public.job_requests(id) on delete set null,
  created_at   timestamptz not null default now()
);

alter table public.feed_posts enable row level security;

create policy "Anyone can view feed posts"
  on public.feed_posts for select
  using (true);

create policy "Users can insert own posts"
  on public.feed_posts for insert
  with check (auth.uid() = author_id);

create policy "Users can update own posts"
  on public.feed_posts for update
  using (auth.uid() = author_id);

-- ─── 8. NOTIFICATIONS ───────────────────────────────────────
create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.users(id) on delete cascade,
  type       text not null,
  title      text not null,
  body       text,
  ref_id     uuid,
  is_read    bool not null default false,
  created_at timestamptz not null default now()
);

alter table public.notifications enable row level security;

create policy "Users see own notifications"
  on public.notifications for select
  using (auth.uid() = user_id);

create policy "Users can mark notifications read"
  on public.notifications for update
  using (auth.uid() = user_id);

-- ─── REALTIME ───────────────────────────────────────────────
-- Activează realtime pentru tabelele critice
alter publication supabase_realtime add table public.sos_alerts;
alter publication supabase_realtime add table public.bids;
alter publication supabase_realtime add table public.notifications;
alter publication supabase_realtime add table public.feed_posts;

-- ─── TRIGGER: auto-creare profil user la înregistrare ───────
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, phone)
  values (new.id, new.phone);
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─── TRIGGER: actualizare rating meseriaș după review ───────
create or replace function public.update_meserias_rating()
returns trigger as $$
begin
  update public.meserias_profiles
  set
    rating_avg = (
      select round(avg(rating)::numeric, 2)
      from public.reviews
      where meserias_id = new.meserias_id
    ),
    rating_count = (
      select count(*)
      from public.reviews
      where meserias_id = new.meserias_id
    )
  where user_id = new.meserias_id;
  return new;
end;
$$ language plpgsql security definer;

create trigger on_review_created
  after insert on public.reviews
  for each row execute function public.update_meserias_rating();
