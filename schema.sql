-- ===========================================================================
--  NMAO PLATFORM - LIVE SCHEMA REFERENCE  (public schema)
--  Reconstructed from a live information_schema dump on 2026-06-29.
--
--  !!  DO NOT RUN THIS FILE AGAINST THE DATABASE.  !!
--  It documents the CURRENT live structure for reference only. Running it
--  would collide with every existing table. To CHANGE the DB, write a
--  targeted ALTER/CREATE migration, not a rebuild.
--
--  Captured by this dump:  table names, column names, data types,
--                          nullability, column defaults.
--  NOT captured (need separate introspection if wanted):
--    - foreign-key / unique / check constraints (the '-- ->' notes below
--      are LOGICAL references inferred from naming + code, not proof a
--      DB constraint exists)
--    - indexes (incl. the schedule_shifts GiST no-overlap exclusion)
--    - RLS policies and SECURITY DEFINER helper functions
--    - triggers (e.g. handle_attendance_deduction) and ~29 RPCs
--    - views (e.g. prospect_source_stats, prospect_accreditation_counts)
--
--  Tables: 92   Columns: 1201
-- ===========================================================================

-- -------------------------------------------------------------------------
--  CORE / TENANCY
--  One row per school. schools is the tenant root; nearly every table FKs
--  to schools.id.
-- -------------------------------------------------------------------------

CREATE TABLE schools (
  id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at                  TIMESTAMPTZ DEFAULT now(),
  name                        TEXT NOT NULL,
  owner_id                    UUID,                                         -- -> auth.users
  email                       TEXT,
  phone                       TEXT,
  address                     TEXT,
  city                        TEXT,
  state                       TEXT,
  zip                         TEXT,
  website                     TEXT,
  logo_url                    TEXT,
  bio                         TEXT,
  styles                      TEXT[],
  plan                        TEXT DEFAULT 'starter',
  plan_price                  NUMERIC,
  plan_status                 TEXT DEFAULT 'active',
  stripe_customer_id          TEXT,
  stripe_subscription_id      TEXT,
  is_active                   BOOLEAN DEFAULT true,
  is_verified                 BOOLEAN DEFAULT false,
  member_count                INTEGER DEFAULT 0,
  slug                        TEXT,
  primary_color               TEXT DEFAULT '#C9A84C',
  background_color            TEXT DEFAULT '#080808',
  accent_color                TEXT DEFAULT '#F5F0E8',
  tagline                     TEXT,
  portal_welcome              TEXT,
  color                       TEXT DEFAULT '#C9A84C',
  milestone_messages          JSONB DEFAULT '{}'::jsonb,
  bg_color                    TEXT DEFAULT '#0A0A0A',
  border_color                TEXT DEFAULT '#2A2520',
  font_family                 TEXT DEFAULT 'Cormorant Garamond',
  pass_fees_to_students       BOOLEAN DEFAULT false,
  surface_color               TEXT DEFAULT '#141414',
  store_featured_blurb        TEXT,
  trial_days                  INTEGER DEFAULT 90,
  trial_ends_at               TIMESTAMPTZ,
  font_color                  TEXT DEFAULT '#F5F0E8',
  setup_dismissed             BOOLEAN DEFAULT false,
  kiosk_video_url             TEXT,
  kiosk_bio                   TEXT,
  kiosk_stats                 JSONB DEFAULT '[]'::jsonb,
  kiosk_instagram_url         TEXT,
  kiosk_facebook_url          TEXT,
  kiosk_tiktok_url            TEXT,
  kiosk_show_video            BOOLEAN DEFAULT false,
  kiosk_show_bio              BOOLEAN DEFAULT false,
  kiosk_show_stats            BOOLEAN DEFAULT false,
  kiosk_show_instagram        BOOLEAN DEFAULT false,
  kiosk_show_facebook         BOOLEAN DEFAULT false,
  kiosk_show_tiktok           BOOLEAN DEFAULT false,
  stripe_account_id           TEXT,
  stripe_onboarded            BOOLEAN DEFAULT false,
  payment_processor           TEXT DEFAULT 'stripe',
  processor_config            JSONB DEFAULT '{}'::jsonb,
  session_pack_low_threshold  INTEGER DEFAULT 2,
  no_show_policy              BOOLEAN DEFAULT false,
  no_show_hours               INTEGER DEFAULT 2,
  late_cancel_policy          BOOLEAN DEFAULT false,
  late_cancel_hours           INTEGER DEFAULT 24,
  late_cancel_action          TEXT DEFAULT 'deduct',
  late_cancel_fee             NUMERIC DEFAULT 0,
  grace_period_count          INTEGER DEFAULT 1,
  referral_reward_type        TEXT DEFAULT 'session',
  referral_reward_value       NUMERIC DEFAULT 1,
  referral_reward_trigger     TEXT DEFAULT 'member',
  two_way_sms_enabled         BOOLEAN DEFAULT false,
  birthday_text_enabled       BOOLEAN DEFAULT true,
  class_reminder_enabled      BOOLEAN DEFAULT true,
  class_reminder_hours        INTEGER DEFAULT 2,
  stripe_connected            BOOLEAN DEFAULT false,
  stripe_connected_at         TIMESTAMPTZ,
  welcomed                    BOOLEAN DEFAULT false,
  subscription_tier_id        UUID,                                         -- -> school_subscription_tiers.id
  is_founding_member          BOOLEAN NOT NULL DEFAULT false,
  founding_member_number      INTEGER,
  subscription_term           TEXT NOT NULL DEFAULT 'monthly',
  subscription_locked_until   DATE,
  platform_fee_override       NUMERIC,
  founding_purchase_date      DATE,
  refund_window_expires_at    TIMESTAMPTZ,
  max_rollover_balance        INTEGER,
  alert_auto_expire_days      INTEGER DEFAULT 30,
  sidebar_text_color          TEXT,
  brand_templates             JSONB,
  allow_member_card_updates   BOOLEAN NOT NULL DEFAULT true,
  twilio_phone                TEXT,
  twilio_phone_normalized     TEXT,
  sms_forward_number          TEXT,
  public_booking_show_spots   BOOLEAN NOT NULL DEFAULT true,
  public_booking_default_view TEXT NOT NULL DEFAULT 'week',
  public_booking_headline     TEXT,
  trial_nudges_sent           JSONB NOT NULL DEFAULT '[]'::jsonb,
  trial_sms_used              INTEGER NOT NULL DEFAULT 0,
  platform_fee_cap_cents      INTEGER NOT NULL DEFAULT 20000
);

CREATE TABLE school_admins (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at TIMESTAMPTZ DEFAULT now(),
  school_id  UUID,                                         -- -> schools.id
  user_id    UUID,                                         -- -> auth.users
  role       TEXT DEFAULT 'admin'
);

CREATE TABLE school_subscription_tiers (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tier_key                TEXT NOT NULL,
  tier_name               TEXT NOT NULL,
  tier_order              INTEGER NOT NULL,
  max_students            INTEGER,
  monthly_price_cents     INTEGER NOT NULL,
  annual_price_cents      INTEGER,
  included_sms            INTEGER NOT NULL,
  overage_per_sms_cents   INTEGER NOT NULL DEFAULT 3,
  stripe_product_id       TEXT,
  stripe_monthly_price_id TEXT,
  stripe_annual_price_id  TEXT,
  active                  BOOLEAN NOT NULL DEFAULT true,
  description             TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE platform_config (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key        TEXT NOT NULL,
  value      TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- -------------------------------------------------------------------------
--  PROGRAMS & CURRICULUM
--  Programs, belt systems/levels, tests, promotions, training videos.
-- -------------------------------------------------------------------------

CREATE TABLE programs (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id      UUID NOT NULL,                                -- -> schools.id
  name           TEXT NOT NULL,
  description    TEXT,
  age_group      TEXT,
  belt_system    TEXT,
  color          TEXT DEFAULT '#C9A84C',
  active         BOOLEAN DEFAULT true,
  created_at     TIMESTAMPTZ DEFAULT now(),
  belt_system_id UUID                                          -- -> belt_systems.id
);

CREATE TABLE belt_systems (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id   UUID NOT NULL,                                -- -> schools.id
  name        TEXT NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE belt_levels (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id        UUID NOT NULL,                                -- -> schools.id
  program_id       UUID,                                         -- -> programs.id
  name             TEXT NOT NULL,
  color_hex        TEXT NOT NULL DEFAULT '#FFFFFF',
  sort_order       INTEGER DEFAULT 0,
  youtube_url      TEXT,
  description      TEXT,
  created_at       TIMESTAMPTZ DEFAULT now(),
  belt_system_id   UUID,                                         -- -> belt_systems.id
  promotion_fee    NUMERIC DEFAULT 0,
  classes_required INTEGER DEFAULT 0
);

CREATE TABLE belt_level_videos (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  belt_level_id UUID NOT NULL,                                -- -> belt_levels.id
  youtube_url   TEXT NOT NULL,
  description   TEXT,
  sort_order    INTEGER DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE belt_tests (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id        UUID NOT NULL,                                -- -> schools.id
  name             TEXT NOT NULL,
  test_date        DATE NOT NULL,
  program_id       UUID,                                         -- -> programs.id
  fee              NUMERIC DEFAULT 0,
  notes            TEXT,
  created_at       TIMESTAMPTZ DEFAULT now(),
  test_time        TIME,
  location         TEXT,
  fee_enabled      BOOLEAN DEFAULT false,
  test_fee         NUMERIC DEFAULT 0,
  payment_method   TEXT DEFAULT 'portal',
  eligibility_rule TEXT DEFAULT 'manual',
  status           TEXT DEFAULT 'upcoming'
);

CREATE TABLE belt_test_students (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  belt_test_id        UUID NOT NULL,                                -- -> belt_tests.id
  student_id          UUID NOT NULL,                                -- -> students.id
  passed              BOOLEAN,
  fee_paid            BOOLEAN DEFAULT false,
  notes               TEXT,
  school_id           UUID NOT NULL,                                -- -> schools.id
  status              TEXT DEFAULT 'pending',
  fee_amount          NUMERIC,
  paid_at             TIMESTAMPTZ,
  invited_at          TIMESTAMPTZ,
  invitation_seen     BOOLEAN DEFAULT false,
  target_belt_id      UUID,                                         -- -> belt_levels.id
  auto_promote_at     TIMESTAMPTZ,
  promotion_processed BOOLEAN DEFAULT false,
  held_back           BOOLEAN DEFAULT false,
  promotion_seen      BOOLEAN DEFAULT false
);

CREATE TABLE belt_promotions (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id      UUID NOT NULL,                                -- -> schools.id
  student_id     UUID NOT NULL,                                -- -> students.id
  belt_from      TEXT,
  belt_to        TEXT,
  belt_from_id   UUID,                                         -- -> belt_levels.id
  belt_to_id     UUID,                                         -- -> belt_levels.id
  promoted_at    TIMESTAMPTZ DEFAULT now(),
  promotion_date DATE,
  promoted_by    TEXT,
  fee_charged    NUMERIC DEFAULT 0,
  fee_paid       BOOLEAN DEFAULT false,
  notes          TEXT,
  belt_test_id   UUID                                          -- -> belt_tests.id
);

-- -------------------------------------------------------------------------
--  MEMBERSHIPS
--  Plan definitions + the student_memberships junction (canonical source
--  of truth; students.membership_id is the deprecated pointer).
-- -------------------------------------------------------------------------

CREATE TABLE memberships (
  id                         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id                  UUID NOT NULL,                                -- -> schools.id
  program_id                 UUID,                                         -- -> programs.id
  name                       TEXT NOT NULL,
  billing_type               TEXT DEFAULT 'monthly',
  billing_length             INTEGER DEFAULT 1,
  billing_unit               TEXT DEFAULT 'months',
  price                      NUMERIC NOT NULL DEFAULT 0,
  signup_fee                 NUMERIC DEFAULT 0,
  class_limit_type           TEXT DEFAULT 'unlimited',
  class_limit_count          INTEGER,
  trial                      BOOLEAN DEFAULT false,
  auto_renew                 BOOLEAN DEFAULT true,
  autopay                    BOOLEAN DEFAULT true,
  active                     BOOLEAN DEFAULT true,
  created_at                 TIMESTAMPTZ DEFAULT now(),
  visibility                 TEXT DEFAULT 'public',
  featured                   BOOLEAN DEFAULT false,
  limited_time               BOOLEAN DEFAULT false,
  offer_start                DATE,
  offer_end                  DATE,
  autopay_day                TEXT DEFAULT 'anniversary',
  description                TEXT,
  class_reservation_eligible BOOLEAN DEFAULT true,
  rollover_enabled           BOOLEAN DEFAULT false,
  cycle_length               INTEGER,
  cycle_unit                 TEXT,
  pack_expiry_days           INTEGER,
  is_custom                  BOOLEAN NOT NULL DEFAULT false,
  public_join_enabled        BOOLEAN NOT NULL DEFAULT false,
  public_headline            TEXT,
  public_blurb               TEXT,
  commitment_length          INTEGER,
  commitment_unit            TEXT DEFAULT 'months',
  early_cancel_fee_type      TEXT DEFAULT 'none',
  early_cancel_fee_amount    NUMERIC DEFAULT 0,
  auto_charge_penalty        BOOLEAN DEFAULT false,
  allow_member_self_cancel   BOOLEAN DEFAULT false
);

CREATE TABLE membership_programs (
  membership_id UUID NOT NULL,  -- -> memberships.id
  program_id    UUID NOT NULL   -- -> programs.id
);
-- (no surrogate id; primary key is composite/natural -- not captured by this dump)

CREATE TABLE membership_classes (
  membership_id UUID NOT NULL,                       -- -> memberships.id
  class_id      UUID NOT NULL,                       -- -> classes.id
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- (no surrogate id; primary key is composite/natural -- not captured by this dump)

CREATE TABLE membership_discounts (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  membership_id UUID NOT NULL,                                -- -> memberships.id
  discount_id   UUID NOT NULL,                                -- -> discounts.id
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE membership_embeds (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id          UUID NOT NULL,                               -- -> schools.id
  name               TEXT NOT NULL,
  membership_ids     JSONB NOT NULL DEFAULT '[]'::jsonb,
  respect_visibility BOOLEAN NOT NULL DEFAULT false,
  active             BOOLEAN NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE student_memberships (
  id                            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id                     UUID NOT NULL,                                -- -> schools.id
  student_id                    UUID NOT NULL,                                -- -> students.id
  membership_id                 UUID NOT NULL,                                -- -> memberships.id
  program_id                    UUID,                                         -- -> programs.id
  status                        TEXT DEFAULT 'active',
  start_date                    DATE,
  created_at                    TIMESTAMPTZ DEFAULT now(),
  stripe_subscription_id        TEXT,
  last_payment_at               TIMESTAMPTZ,
  ended_at                      TIMESTAMPTZ,
  started_at                    TIMESTAMPTZ,
  classes_used                  INTEGER NOT NULL DEFAULT 0,
  expires_at                    TIMESTAMPTZ,
  cycle_start_date              DATE,
  cycle_end_date                DATE,
  cycle_allowance               INTEGER,
  classes_remaining             INTEGER,
  rollover_balance              INTEGER DEFAULT 0,
  price                         NUMERIC,
  autopay                       BOOLEAN DEFAULT false,
  expiry_reminder_sent_at       TIMESTAMPTZ,
  awaiting_card                 BOOLEAN DEFAULT false,
  first_charge_date             DATE,
  is_class_pack                 BOOLEAN NOT NULL DEFAULT false,
  commitment_ends_at            DATE,
  commit_fee_type               TEXT,
  commit_fee_amount             NUMERIC,
  cancel_policy_accepted_at     TIMESTAMPTZ,
  early_cancel_fee_owed         NUMERIC,
  early_cancel_fee_collected_at TIMESTAMPTZ
);

CREATE TABLE discounts (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id    UUID NOT NULL,                                -- -> schools.id
  name         TEXT NOT NULL,
  method       TEXT DEFAULT 'percentage',
  amount       NUMERIC DEFAULT 0,
  applies_to   TEXT DEFAULT 'both',
  online_code  TEXT,
  visibility   TEXT DEFAULT 'staff',
  status       TEXT DEFAULT 'active',
  valid_from   DATE,
  valid_until  DATE,
  usage_limit  INTEGER,
  usage_count  INTEGER DEFAULT 0,
  multiple_use BOOLEAN DEFAULT true,
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- -------------------------------------------------------------------------
--  CLASSES (group flow)
--  Recurring class defs, generated sessions, attendance, reservations,
--  waitlist, pack-credit grants, and white-label option lookups.
-- -------------------------------------------------------------------------

CREATE TABLE classes (
  id                     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at             TIMESTAMPTZ DEFAULT now(),
  school_id              UUID,                                         -- -> schools.id
  title                  TEXT NOT NULL,
  style                  TEXT,
  level                  TEXT,
  age_group              TEXT,
  instructor_name        TEXT,
  location               TEXT,
  is_fixed               BOOLEAN DEFAULT true,
  days_of_week           TEXT[],
  start_time             TIME,
  end_time               TIME,
  start_date             DATE,
  end_date               DATE,
  capacity               INTEGER,
  color                  TEXT DEFAULT '#C9A84C',
  is_active              BOOLEAN DEFAULT true,
  notes                  TEXT,
  description            TEXT,
  name                   TEXT,
  active                 BOOLEAN DEFAULT true,
  show_instructor_on_app BOOLEAN DEFAULT true,
  program_id             UUID,                                         -- -> programs.id
  public_booking_enabled BOOLEAN NOT NULL DEFAULT false,
  trial_enabled          BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE class_sessions (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  class_id       UUID,                                         -- -> classes.id
  school_id      UUID,                                         -- -> schools.id
  session_date   DATE NOT NULL,
  start_time     TIME,
  end_time       TIME,
  status         TEXT DEFAULT 'scheduled',
  notes          TEXT,
  attendee_count INTEGER DEFAULT 0
);

CREATE TABLE class_enrollments (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id        UUID NOT NULL,                                -- -> schools.id
  class_id         UUID NOT NULL,                                -- -> classes.id
  student_id       UUID NOT NULL,                                -- -> students.id
  session_date     DATE,
  status           TEXT DEFAULT 'enrolled',
  created_at       TIMESTAMPTZ DEFAULT now(),
  reminder_sent_at TIMESTAMPTZ
);

CREATE TABLE class_reservations (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id    UUID,                                        -- -> schools.id
  class_id     UUID,                                        -- -> classes.id
  student_id   UUID,                                        -- -> students.id
  session_date DATE,
  status       TEXT DEFAULT 'reserved',
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE class_attendance (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id     UUID,
  student_id     UUID,                                         -- -> students.id
  school_id      UUID,                                         -- -> schools.id
  status         TEXT DEFAULT 'present',
  noted_at       TIMESTAMPTZ DEFAULT now(),
  deducted_sm_id UUID                                          -- -> student_memberships.id
);

CREATE TABLE class_waitlist (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id      UUID NOT NULL,                               -- -> schools.id
  student_id     UUID NOT NULL,                               -- -> students.id
  class_id       UUID NOT NULL,                               -- -> classes.id
  session_date   DATE NOT NULL,
  has_membership BOOLEAN DEFAULT false,
  notified_at    TIMESTAMPTZ,
  status         TEXT DEFAULT 'waiting',
  created_at     TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE class_credit_grants (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id               UUID NOT NULL,                               -- -> schools.id
  student_id              UUID NOT NULL,                               -- -> students.id
  student_membership_id   UUID,                                        -- -> student_memberships.id
  qty                     INTEGER NOT NULL,
  reason                  TEXT,
  issued_by_instructor_id UUID,                                        -- -> instructors.id
  issued_by_name          TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE class_age_options (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id  UUID,                                         -- -> schools.id
  label      TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0
);

CREATE TABLE class_level_options (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id  UUID,                                         -- -> schools.id
  label      TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0
);

CREATE TABLE class_style_options (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id  UUID,                                         -- -> schools.id
  label      TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0
);

CREATE TABLE class_field_options (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id  UUID,                                         -- -> schools.id
  field_key  TEXT NOT NULL,
  label      TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0
);

CREATE TABLE class_field_settings (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id   UUID,                                         -- -> schools.id
  field_key   TEXT NOT NULL,
  field_label TEXT NOT NULL,
  show_on_app BOOLEAN DEFAULT true,
  sort_order  INTEGER DEFAULT 0
);

-- -------------------------------------------------------------------------
--  PRIVATE SESSIONS (1-on-1 flow)
--  Bookable session types, scheduled/recurring sessions, session packs,
--  notes/ratings, no-show log, instructor availability & payroll.
-- -------------------------------------------------------------------------

CREATE TABLE session_types (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id             UUID,                                         -- -> schools.id
  name                  TEXT NOT NULL,
  duration_minutes      INTEGER DEFAULT 60,
  capacity              INTEGER DEFAULT 1,
  price                 NUMERIC DEFAULT 0,
  description           TEXT,
  color                 TEXT DEFAULT '#7DAAD4',
  active                BOOLEAN DEFAULT true,
  created_at            TIMESTAMPTZ DEFAULT now(),
  available_for_booking BOOLEAN DEFAULT true,
  show_in_portal        BOOLEAN DEFAULT true
);

CREATE TABLE sessions (
  id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id               UUID,                                         -- -> schools.id
  session_type_id         UUID,                                         -- -> session_types.id
  student_id              UUID,                                         -- -> students.id
  instructor_id           UUID,                                         -- -> instructors.id
  session_date            DATE NOT NULL,
  start_time              TIME NOT NULL,
  duration_minutes        INTEGER,
  status                  TEXT DEFAULT 'scheduled',
  notes                   TEXT,
  created_at              TIMESTAMPTZ DEFAULT now(),
  confirmation_token      TEXT,
  confirmation_status     TEXT DEFAULT 'pending',
  reminder_sent_at        TIMESTAMPTZ,
  student_session_pack_id UUID,                                         -- -> student_session_packs.id
  sessions_deducted       BOOLEAN DEFAULT false,
  recurring_id            UUID,                                         -- -> recurring_sessions.id
  substitute_instructor   TEXT,
  is_recurring            BOOLEAN DEFAULT false,
  no_show                 BOOLEAN DEFAULT false,
  no_show_processed_at    TIMESTAMPTZ,
  late_cancel             BOOLEAN DEFAULT false,
  rating                  INTEGER,
  rating_received_at      TIMESTAMPTZ,
  instructor_name         TEXT,
  price                   NUMERIC
);

CREATE TABLE recurring_sessions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id        UUID NOT NULL,                               -- -> schools.id
  student_id       UUID,                                        -- -> students.id
  instructor_id    UUID,                                        -- -> instructors.id
  session_type_id  UUID,                                        -- -> session_types.id
  day_of_week      TEXT NOT NULL,
  start_time       TIME NOT NULL,
  duration_minutes INTEGER DEFAULT 60,
  start_date       DATE NOT NULL,
  end_date         DATE,
  active           BOOLEAN DEFAULT true,
  created_at       TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE session_packs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL,                               -- -> schools.id
  session_type_id UUID,                                        -- -> session_types.id
  name            TEXT NOT NULL,
  quantity        INTEGER NOT NULL DEFAULT 1,
  price           NUMERIC NOT NULL DEFAULT 0,
  expiry_days     INTEGER DEFAULT 90,
  show_in_portal  BOOLEAN DEFAULT true,
  show_in_retail  BOOLEAN DEFAULT true,
  active          BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now(),
  description     TEXT,
  kind            TEXT NOT NULL DEFAULT 'class'
);

CREATE TABLE student_session_packs (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id          UUID NOT NULL,                               -- -> schools.id
  student_id         UUID NOT NULL,                               -- -> students.id
  session_pack_id    UUID,                                        -- -> session_packs.id
  session_type_id    UUID,                                        -- -> session_types.id
  name               TEXT,
  sessions_total     INTEGER NOT NULL DEFAULT 0,
  sessions_remaining INTEGER NOT NULL DEFAULT 0,
  purchased_at       TIMESTAMPTZ DEFAULT now(),
  expires_at         TIMESTAMPTZ,
  status             TEXT DEFAULT 'active',
  payment_id         UUID,                                        -- -> payments.id
  gift_card_id       UUID,                                        -- -> gift_cards.id
  created_at         TIMESTAMPTZ DEFAULT now(),
  reminder_sent_at   TIMESTAMPTZ,
  pack_kind          TEXT NOT NULL,
  notes              TEXT
);

CREATE TABLE session_notes (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id          UUID NOT NULL,                               -- -> schools.id
  session_id         UUID NOT NULL,
  student_id         UUID,                                        -- -> students.id
  instructor_id      UUID,                                        -- -> instructors.id
  content            TEXT,
  homework           TEXT,
  youtube_urls       JSONB DEFAULT '[]'::jsonb,
  visible_to_student BOOLEAN DEFAULT true,
  created_at         TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE session_ratings (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL,                               -- -> schools.id
  session_id    UUID NOT NULL,
  student_id    UUID,                                        -- -> students.id
  instructor_id UUID,                                        -- -> instructors.id
  rating        INTEGER NOT NULL,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE session_settings (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id                UUID,                                        -- -> schools.id
  no_show_window_hours     INTEGER DEFAULT 2,
  no_show_action           TEXT DEFAULT 'No Action',
  late_cancel_window_hours INTEGER DEFAULT 24,
  late_cancel_action       TEXT DEFAULT 'No Action',
  grace_period             INTEGER DEFAULT 1,
  low_pack_threshold       INTEGER DEFAULT 2,
  created_at               TIMESTAMPTZ DEFAULT now(),
  updated_at               TIMESTAMPTZ DEFAULT now(),
  grace_period_count       INTEGER DEFAULT 1,
  late_cancel_fee          NUMERIC DEFAULT 0,
  late_cancel_hours        INTEGER DEFAULT 24,
  session_reminder_enabled BOOLEAN DEFAULT true,
  pack_reminder_enabled    BOOLEAN DEFAULT true
);

CREATE TABLE session_waitlist (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL,                               -- -> schools.id
  student_id      UUID NOT NULL,                               -- -> students.id
  instructor_id   UUID,                                        -- -> instructors.id
  session_type_id UUID,                                        -- -> session_types.id
  requested_date  DATE,
  requested_time  TIME,
  has_pack        BOOLEAN DEFAULT false,
  notified_at     TIMESTAMPTZ,
  status          TEXT DEFAULT 'waiting',
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE session_wishlist (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL,                               -- -> schools.id
  student_id      UUID NOT NULL,                               -- -> students.id
  session_type_id UUID,                                        -- -> session_types.id
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE no_show_log (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL,                               -- -> schools.id
  session_id    UUID,
  student_id    UUID NOT NULL,                               -- -> students.id
  session_date  DATE,
  action_taken  TEXT,
  pack_deducted BOOLEAN DEFAULT false,
  fee_charged   NUMERIC DEFAULT 0,
  waived        BOOLEAN DEFAULT false,
  waive_reason  TEXT,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE instructor_availability (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL,                               -- -> schools.id
  instructor_id   UUID NOT NULL,                               -- -> instructors.id
  session_type_id UUID,                                        -- -> session_types.id
  day_of_week     TEXT NOT NULL,
  start_time      TIME NOT NULL,
  end_time        TIME NOT NULL,
  active          BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE instructor_availability_exceptions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id      UUID NOT NULL,                               -- -> schools.id
  instructor_id  UUID NOT NULL,                               -- -> instructors.id
  exception_date DATE NOT NULL,
  reason         TEXT,
  created_at     TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE instructor_booking_settings (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id           UUID NOT NULL,                               -- -> schools.id
  instructor_id       UUID NOT NULL,                               -- -> instructors.id
  buffer_minutes      INTEGER DEFAULT 15,
  cancel_window_hours INTEGER DEFAULT 24,
  max_advance_days    INTEGER DEFAULT 30,
  booking_link_active BOOLEAN DEFAULT true,
  welcome_message     TEXT,
  created_at          TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE instructor_payroll (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id      UUID NOT NULL,                               -- -> schools.id
  instructor_id  UUID NOT NULL,                               -- -> instructors.id
  period_start   DATE NOT NULL,
  period_end     DATE NOT NULL,
  sessions_count INTEGER DEFAULT 0,
  total_earned   NUMERIC DEFAULT 0,
  status         TEXT DEFAULT 'pending',
  notes          TEXT,
  created_at     TIMESTAMPTZ DEFAULT now()
);

-- -------------------------------------------------------------------------
--  PEOPLE (students / families / staff / leads)
--  Students, families, instructors, the in-school CRM (leads), tags,
--  goals, directory, internal messages.
-- -------------------------------------------------------------------------

CREATE TABLE students (
  id                           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at                   TIMESTAMPTZ DEFAULT now(),
  user_id                      UUID,                                         -- -> auth.users
  school_id                    UUID,                                         -- -> schools.id
  first_name                   TEXT NOT NULL,
  last_name                    TEXT NOT NULL,
  email                        TEXT,
  phone                        TEXT,
  date_of_birth                DATE,
  address                      TEXT,
  city                         TEXT,
  state                        TEXT,
  zip                          TEXT,
  avatar_url                   TEXT,
  emergency_contact_name       TEXT,
  emergency_contact_phone      TEXT,
  membership_status            TEXT DEFAULT 'active',
  membership_start             DATE,
  membership_end               DATE,
  membership_plan              TEXT,
  belt_awarded_date            DATE,
  stripes                      INTEGER DEFAULT 0,
  show_in_directory            BOOLEAN DEFAULT true,
  directory_bio                TEXT,
  notes                        TEXT,
  waiver_signed                BOOLEAN DEFAULT false,
  waiver_signed_at             TIMESTAMPTZ,
  program_id                   UUID,                                         -- -> programs.id
  membership_id                UUID,                                         -- -> memberships.id
  start_date                   DATE,
  plan_type                    TEXT DEFAULT 'membership',
  status                       TEXT DEFAULT 'trial',
  photo_url                    TEXT,
  current_belt_id              UUID,                                         -- -> belt_levels.id
  membership_end_date          DATE,
  family_id                    UUID,                                         -- -> families.id
  autopay_day_override         TEXT,
  paused_at                    TIMESTAMPTZ,
  reactivated_at               TIMESTAMPTZ,
  portal_onboarded             BOOLEAN DEFAULT false,
  celebrated_milestones        INTEGER[] DEFAULT '{}'::integer[],
  referral_code                TEXT,
  referred_by_student_id       UUID,                                         -- -> students.id
  weekly_streak                INTEGER DEFAULT 0,
  longest_streak               INTEGER DEFAULT 0,
  streak_updated_at            TIMESTAMPTZ,
  portal_pin                   TEXT,
  last_portal_login            TIMESTAMPTZ,
  stripe_customer_id           TEXT,
  portal_invited_at            TIMESTAMPTZ,
  mother_name                  TEXT,
  father_name                  TEXT,
  deleted_at                   TIMESTAMPTZ,
  password_set                 BOOLEAN NOT NULL DEFAULT false,
  phone_normalized             TEXT,
  sms_consent                  BOOLEAN,
  sms_consent_at               TIMESTAMPTZ,
  source                       TEXT,
  stripe_connected_customer_id TEXT
);

CREATE TABLE families (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id         UUID NOT NULL,                                -- -> schools.id
  name              TEXT NOT NULL,
  email             TEXT,
  phone             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  notes             TEXT,
  portal_invited_at TIMESTAMPTZ
);

CREATE TABLE instructors (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id            UUID NOT NULL,                                -- -> schools.id
  user_id              UUID,                                         -- -> auth.users
  first_name           TEXT NOT NULL,
  last_name            TEXT NOT NULL,
  email                TEXT,
  active               BOOLEAN DEFAULT true,
  created_at           TIMESTAMPTZ DEFAULT now(),
  phone                TEXT,
  bio                  TEXT,
  specialties          TEXT,
  photo_url            TEXT,
  booking_link_enabled BOOLEAN DEFAULT false,
  booking_slug         TEXT,
  payroll_rate         NUMERIC DEFAULT 0,
  payroll_type         TEXT DEFAULT 'per_session',
  auth_user_id         UUID,                                         -- -> auth.users
  phone_normalized     TEXT,
  notes                TEXT
);

CREATE TABLE leads (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id          UUID NOT NULL,                                -- -> schools.id
  first_name         TEXT NOT NULL,
  last_name          TEXT NOT NULL,
  email              TEXT,
  phone              TEXT,
  program_id         UUID,                                         -- -> programs.id
  source             TEXT,
  status             TEXT DEFAULT 'new',
  notes              TEXT,
  created_at         TIMESTAMPTZ DEFAULT now(),
  photo_url          TEXT,
  sms_consent        BOOLEAN,
  sms_consent_at     TIMESTAMPTZ,
  deleted_at         TIMESTAMPTZ,
  trial_redeemed_at  TIMESTAMPTZ,
  trial_class_id     UUID,
  trial_session_date DATE,
  converted_at       TIMESTAMPTZ
);

CREATE TABLE tags (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id        UUID NOT NULL,                                -- -> schools.id
  name             TEXT NOT NULL,
  color            TEXT DEFAULT '#C9A84C',
  description      TEXT,
  auto_assign_rule TEXT,
  created_at       TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE student_tags (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id  UUID NOT NULL,                                -- -> schools.id
  student_id UUID NOT NULL,                                -- -> students.id
  tag_id     UUID NOT NULL,                                -- -> tags.id
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE student_goals (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL,                               -- -> schools.id
  student_id    UUID NOT NULL,                               -- -> students.id
  instructor_id UUID,                                        -- -> instructors.id
  goal          TEXT NOT NULL,
  target_date   DATE,
  status        TEXT DEFAULT 'active',
  completed_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE directory_profiles (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  updated_at    TIMESTAMPTZ DEFAULT now(),
  school_id     UUID,                                         -- -> schools.id
  display_name  TEXT,
  tagline       TEXT,
  bio           TEXT,
  styles        TEXT[],
  logo_url      TEXT,
  city          TEXT,
  state         TEXT,
  website       TEXT,
  is_visible    BOOLEAN DEFAULT true,
  student_count INTEGER DEFAULT 0,
  is_verified   BOOLEAN DEFAULT false
);

CREATE TABLE messages (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id  UUID NOT NULL,                                -- -> schools.id
  student_id UUID NOT NULL,                                -- -> students.id
  sent_by    UUID,
  body       TEXT NOT NULL,
  read       BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- -------------------------------------------------------------------------
--  EVENTS (incl. partial-attendance tiers)
--  Events, per-day sessions w/ per-session capacity, price tiers,
--  registrations, the day-picker junction, waitlist.
-- -------------------------------------------------------------------------

CREATE TABLE events (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id             UUID NOT NULL,                                -- -> schools.id
  title                 TEXT NOT NULL,
  description           TEXT,
  event_type            TEXT DEFAULT 'seminar',
  is_multi_session      BOOLEAN DEFAULT false,
  location              TEXT,
  staff_member          TEXT,
  guest_instructor      TEXT,
  calendar_color        TEXT DEFAULT '#7DAAD4',
  capacity              INTEGER,
  registration_deadline DATE,
  registration_status   TEXT DEFAULT 'open',
  show_on_portal        BOOLEAN DEFAULT true,
  notify_staff          BOOLEAN DEFAULT true,
  waitlist_enabled      BOOLEAN DEFAULT false,
  active                BOOLEAN DEFAULT true,
  created_at            TIMESTAMPTZ DEFAULT now(),
  event_date            DATE,
  start_time            TIME,
  end_time              TIME,
  ticket_price          NUMERIC DEFAULT 0,
  visibility            TEXT DEFAULT 'students',
  public_signup_enabled BOOLEAN DEFAULT false
);

CREATE TABLE event_sessions (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_id         UUID NOT NULL,                                -- -> events.id
  school_id        UUID NOT NULL,                                -- -> schools.id
  session_date     DATE NOT NULL,
  start_time       TIME,
  duration_minutes INTEGER DEFAULT 60,
  end_time         TIME,
  sort_order       INTEGER DEFAULT 0,
  created_at       TIMESTAMPTZ DEFAULT now(),
  capacity         INTEGER
);

CREATE TABLE event_price_tiers (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_id          UUID NOT NULL,                                -- -> events.id
  school_id         UUID NOT NULL,                                -- -> schools.id
  label             TEXT NOT NULL,
  price             NUMERIC DEFAULT 0,
  availability      TEXT DEFAULT 'public',
  program_id        UUID,                                         -- -> programs.id
  visible           BOOLEAN DEFAULT true,
  sessions_included INTEGER DEFAULT 0,
  visibility        TEXT DEFAULT 'public',
  available_until   DATE,
  sort_order        INTEGER DEFAULT 0,
  created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE event_registrations (
  id                         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id                  UUID NOT NULL,                                -- -> schools.id
  event_id                   UUID NOT NULL,                                -- -> events.id
  student_id                 UUID,                                         -- -> students.id
  price_tier_id              UUID,                                         -- -> event_price_tiers.id
  amount_paid                NUMERIC DEFAULT 0,
  paid                       BOOLEAN DEFAULT false,
  checked_in                 BOOLEAN DEFAULT false,
  checked_in_at              TIMESTAMPTZ,
  registered_at              TIMESTAMPTZ DEFAULT now(),
  guest_name                 TEXT,
  guest_email                TEXT,
  guest_phone                TEXT,
  amount                     NUMERIC DEFAULT 0,
  paid_at                    TIMESTAMPTZ,
  tier_label                 TEXT,
  payment_method             TEXT,
  stripe_checkout_session_id TEXT,
  fee_passed_cents           INTEGER
);

CREATE TABLE registration_sessions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id        UUID,                                        -- -> schools.id
  registration_id  UUID,                                        -- -> event_registrations.id
  event_session_id UUID,                                        -- -> event_sessions.id
  checked_in       BOOLEAN DEFAULT false,
  checked_in_at    TIMESTAMPTZ,
  created_at       TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE event_waitlist (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id   UUID NOT NULL,                                -- -> schools.id
  event_id    UUID NOT NULL,                                -- -> events.id
  student_id  UUID,                                         -- -> students.id
  name        TEXT,
  email       TEXT,
  phone       TEXT,
  joined_at   TIMESTAMPTZ DEFAULT now(),
  notified    BOOLEAN DEFAULT false,
  guest_name  TEXT,
  guest_email TEXT,
  guest_phone TEXT
);

-- -------------------------------------------------------------------------
--  PAYMENTS / STRIPE CONNECT
--  Canonical payments ledger, split tenders, retries, account credits,
--  gift cards, platform-fee accounting, webhook idempotency, retail
--  products.
-- -------------------------------------------------------------------------

CREATE TABLE payments (
  id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at               TIMESTAMPTZ DEFAULT now(),
  school_id                UUID,                                         -- -> schools.id
  student_id               UUID,                                         -- -> students.id
  type                     TEXT NOT NULL,
  description              TEXT,
  amount                   NUMERIC NOT NULL,
  processing_fee           NUMERIC,
  net_amount               NUMERIC,
  currency                 TEXT DEFAULT 'usd',
  status                   TEXT DEFAULT 'pending',
  stripe_payment_intent_id TEXT,
  stripe_invoice_id        TEXT,
  stripe_charge_id         TEXT,
  event_registration_id    UUID,                                         -- -> event_registrations.id
  invoice_number           TEXT,
  due_date                 DATE,
  paid_at                  TIMESTAMPTZ,
  notes                    TEXT,
  line_items               JSONB,
  fulfilled_at             TIMESTAMPTZ,
  fulfilled_by             UUID,
  fee_passed_cents         INTEGER
);

CREATE TABLE payment_tenders (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id               UUID NOT NULL,                               -- -> payments.id
  school_id                UUID NOT NULL,                               -- -> schools.id
  tender_type              TEXT NOT NULL,
  amount_cents             INTEGER NOT NULL,
  stripe_payment_intent_id TEXT,
  account_credit_id        UUID,                                        -- -> account_credits.id
  created_at               TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE payment_retry_log (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id           UUID NOT NULL,                               -- -> schools.id
  student_id          UUID NOT NULL,                               -- -> students.id
  original_payment_id UUID,                                        -- -> payments.id
  amount              NUMERIC DEFAULT 0,
  attempt_number      INTEGER DEFAULT 1,
  status              TEXT DEFAULT 'pending',
  sms_sent_at         TIMESTAMPTZ,
  membership_paused   BOOLEAN DEFAULT false,
  resolved_at         TIMESTAMPTZ,
  created_at          TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE account_credits (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id    UUID NOT NULL,                               -- -> schools.id
  student_id   UUID NOT NULL,                               -- -> students.id
  amount_cents INTEGER NOT NULL,
  type         TEXT NOT NULL,
  reason       TEXT,
  created_by   UUID,
  payment_id   UUID,                                        -- -> payments.id
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE gift_cards (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id          UUID NOT NULL,                               -- -> schools.id
  code               TEXT NOT NULL,
  session_pack_id    UUID,                                        -- -> session_packs.id
  amount             NUMERIC DEFAULT 0,
  type               TEXT DEFAULT 'session_pack',
  purchased_by_name  TEXT,
  purchased_by_email TEXT,
  recipient_name     TEXT,
  recipient_email    TEXT,
  recipient_phone    TEXT,
  message            TEXT,
  redeemed_by        UUID,
  redeemed_at        TIMESTAMPTZ,
  status             TEXT DEFAULT 'active',
  expires_at         TIMESTAMPTZ,
  payment_id         TEXT,                                        -- -> payments.id
  created_at         TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE platform_fee_processed (
  stripe_fee_id    TEXT NOT NULL,
  school_id        UUID,                                -- -> schools.id
  stripe_charge_id TEXT,
  applied_cents    INTEGER,
  period           TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  reversed_at      TIMESTAMPTZ
);
-- (no surrogate id; primary key is composite/natural -- not captured by this dump)

CREATE TABLE platform_fee_usage (
  school_id         UUID NOT NULL,                       -- -> schools.id
  period            TEXT NOT NULL,
  accrued_fee_cents BIGINT NOT NULL DEFAULT 0,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- (no surrogate id; primary key is composite/natural -- not captured by this dump)

CREATE TABLE processed_webhook_events (
  event_id     TEXT NOT NULL,                       -- -> events.id
  processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- (no surrogate id; primary key is composite/natural -- not captured by this dump)

CREATE TABLE products (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id          UUID NOT NULL,                                -- -> schools.id
  name               TEXT NOT NULL,
  description        TEXT,
  category           TEXT,
  subcategory        TEXT,
  retail_price       NUMERIC DEFAULT 0,
  wholesale_price    NUMERIC DEFAULT 0,
  image_url          TEXT,
  track_inventory    BOOLEAN DEFAULT false,
  inventory_qty      INTEGER DEFAULT 0,
  reorder_qty        INTEGER DEFAULT 0,
  visibility         TEXT DEFAULT 'staff',
  featured           BOOLEAN DEFAULT false,
  member_app         BOOLEAN DEFAULT false,
  active             BOOLEAN DEFAULT true,
  created_at         TIMESTAMPTZ DEFAULT now(),
  quick_list         BOOLEAN DEFAULT false,
  badge_style        TEXT,
  badge_text         TEXT,
  product_type       TEXT DEFAULT 'physical',
  session_pack_id    UUID,                                         -- -> session_packs.id
  is_gift_card       BOOLEAN DEFAULT false,
  updated_at         TIMESTAMPTZ DEFAULT now(),
  public_pay_enabled BOOLEAN NOT NULL DEFAULT false
);

-- -------------------------------------------------------------------------
--  COMMS / SMS / AUTOMATION
--  Broadcasts, portal announcements (also used by Schedule-Shift
--  reminders), SMS inbox/threading, suppression list, usage metering,
--  automation engine.
-- -------------------------------------------------------------------------

CREATE TABLE communications (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at      TIMESTAMPTZ DEFAULT now(),
  school_id       UUID,                                         -- -> schools.id
  created_by      UUID,
  subject         TEXT NOT NULL,
  body            TEXT NOT NULL,
  type            TEXT DEFAULT 'announcement',
  audience        TEXT DEFAULT 'all',
  status          TEXT DEFAULT 'draft',
  sent_at         TIMESTAMPTZ,
  scheduled_for   TIMESTAMPTZ,
  recipient_count INTEGER DEFAULT 0,
  channel         TEXT
);

CREATE TABLE school_announcements (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL,                                -- -> schools.id
  type            TEXT NOT NULL DEFAULT 'announcement',
  subject         TEXT NOT NULL,
  body            TEXT NOT NULL,
  image_urls      JSONB DEFAULT '[]'::jsonb,
  audience        TEXT DEFAULT 'all',
  program_id      UUID,                                         -- -> programs.id
  class_id        UUID,                                         -- -> classes.id
  cta_label       TEXT,
  cta_url         TEXT,
  scheduled_at    TIMESTAMPTZ,
  sent_at         TIMESTAMPTZ,
  status          TEXT DEFAULT 'draft',
  recipient_count INTEGER DEFAULT 0,
  created_by      UUID,
  created_at      TIMESTAMPTZ DEFAULT now(),
  deleted_at      TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ,
  scheduled_for   TIMESTAMPTZ,
  pinned          BOOLEAN NOT NULL DEFAULT false,
  sort_order      INTEGER
);

CREATE TABLE sms_inbox (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id     UUID NOT NULL,                               -- -> schools.id
  student_id    UUID,                                        -- -> students.id
  instructor_id UUID,                                        -- -> instructors.id
  from_phone    TEXT NOT NULL,
  to_phone      TEXT,
  body          TEXT NOT NULL,
  direction     TEXT DEFAULT 'inbound',
  read          BOOLEAN DEFAULT false,
  replied_at    TIMESTAMPTZ,
  reply_body    TEXT,
  twilio_sid    TEXT,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE sms_suppressions (
  phone          TEXT NOT NULL,
  opted_out_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  source         TEXT,
  last_school_id UUID                                 -- -> schools.id
);
-- (no surrogate id; primary key is composite/natural -- not captured by this dump)

CREATE TABLE sms_usage (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id              UUID NOT NULL,                               -- -> schools.id
  period_start           TIMESTAMPTZ NOT NULL,
  period_end             TIMESTAMPTZ NOT NULL,
  sms_count              INTEGER NOT NULL DEFAULT 0,
  sms_bundle             INTEGER NOT NULL,
  overage_count          INTEGER NOT NULL DEFAULT 0,
  overage_amount_cents   INTEGER NOT NULL DEFAULT 0,
  overage_charged        BOOLEAN NOT NULL DEFAULT false,
  stripe_invoice_item_id TEXT,
  warning_80_sent_at     TIMESTAMPTZ,
  warning_100_sent_at    TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE automation_settings (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id     UUID NOT NULL,                                -- -> schools.id
  enabled       BOOLEAN DEFAULT false,
  delay_hours   INTEGER DEFAULT 0,
  subject       TEXT,
  body          TEXT,
  channel       TEXT DEFAULT 'email',
  created_at    TIMESTAMPTZ DEFAULT now(),
  email_enabled BOOLEAN DEFAULT true,
  sms_enabled   BOOLEAN DEFAULT false,
  trigger_key   TEXT
);

CREATE TABLE automation_log (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id      UUID NOT NULL,                               -- -> schools.id
  trigger_key    TEXT NOT NULL,
  recipient_type TEXT,
  recipient_id   UUID,
  email_sent     BOOLEAN DEFAULT false,
  sms_sent       BOOLEAN DEFAULT false,
  status         TEXT,
  detail         TEXT,
  fired_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------------------
--  SCHEDULE SHIFTS
--  Named date-range overrides to the base class schedule + reminder
--  idempotency log. (GiST no-overlap exclusion constraint on
--  schedule_shifts is not shown here.)
-- -------------------------------------------------------------------------

CREATE TABLE schedule_shifts (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id          UUID NOT NULL,                               -- -> schools.id
  name               TEXT NOT NULL,
  start_date         DATE NOT NULL,
  end_date           DATE NOT NULL,
  remind_days_before INTEGER NOT NULL DEFAULT 3,
  remind_revert      BOOLEAN NOT NULL DEFAULT false,
  notify_channels    JSONB NOT NULL DEFAULT '["alert"]'::jsonb,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE schedule_shift_classes (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_id     UUID NOT NULL,                               -- -> schedule_shifts.id
  class_id     UUID NOT NULL,                               -- -> classes.id
  action       TEXT NOT NULL DEFAULT 'retime',
  days_of_week JSONB,
  start_time   TEXT,
  end_time     TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE schedule_shift_reminders_sent (
  id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_id UUID NOT NULL,                               -- -> schedule_shifts.id
  kind     TEXT NOT NULL,
  sent_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------------------
--  WAIVERS / QR
--  Waiver templates, immutable signature records, QR code tracking.
-- -------------------------------------------------------------------------

CREATE TABLE waivers (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id  UUID NOT NULL,                                -- -> schools.id
  title      TEXT NOT NULL,
  content    TEXT NOT NULL,
  active     BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE waiver_signatures (
  id                        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  waiver_id                 UUID NOT NULL,                                -- -> waivers.id
  student_id                UUID NOT NULL,                                -- -> students.id
  signed_at                 TIMESTAMPTZ DEFAULT now(),
  ip_address                TEXT,
  signature                 TEXT,
  school_id                 UUID NOT NULL,                                -- -> schools.id
  signed_template_text      TEXT NOT NULL,
  template_title_at_signing TEXT NOT NULL,
  typed_name                TEXT NOT NULL,
  opt_in_photo              BOOLEAN NOT NULL DEFAULT false,
  opt_in_sms                BOOLEAN NOT NULL DEFAULT false,
  opt_in_email              BOOLEAN NOT NULL DEFAULT false,
  scroll_pct                INTEGER,
  user_agent                TEXT,
  signed_by_family_id       UUID,                                         -- -> families.id
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE qr_codes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_id       UUID NOT NULL,                               -- -> schools.id
  type            TEXT NOT NULL,
  target_id       UUID,
  target_url      TEXT NOT NULL,
  label           TEXT,
  created_by      UUID,
  created_at      TIMESTAMPTZ DEFAULT now(),
  scan_count      INTEGER DEFAULT 0,
  last_scanned_at TIMESTAMPTZ,
  active          BOOLEAN DEFAULT true
);

-- -------------------------------------------------------------------------
--  ONBOARDING / CRM  (NMAO-Onboarding repo, onboard.nmao.us)
--  Cross-repo: specialists, availability, call bookings, prospect
--  pipeline, accreditation tracker. Shares this DB; reached from member
--  tables via SECURITY DEFINER RPCs.
-- -------------------------------------------------------------------------

CREATE TABLE onboarding_specialists (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID,                                        -- -> auth.users
  name               TEXT NOT NULL,
  email              TEXT,
  phone              TEXT,
  timezone           TEXT NOT NULL DEFAULT 'America/New_York',
  zoom_personal_link TEXT,
  active             BOOLEAN NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_admin           BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE onboarding_availability (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  specialist_id UUID NOT NULL,                               -- -> onboarding_specialists.id
  day_of_week   SMALLINT NOT NULL,
  start_time    TIME NOT NULL,
  end_time      TIME NOT NULL,
  active        BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE onboarding_availability_exceptions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  specialist_id  UUID NOT NULL,                               -- -> onboarding_specialists.id
  exception_date DATE NOT NULL,
  kind           TEXT NOT NULL DEFAULT 'blackout',
  start_time     TIME,
  end_time       TIME,
  reason         TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE onboarding_bookings (
  id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  specialist_id              UUID,                                        -- -> onboarding_specialists.id
  school_id                  UUID,                                        -- -> schools.id
  owner_user_id              UUID,                                        -- -> auth.users
  owner_name                 TEXT,
  owner_email                TEXT,
  owner_phone                TEXT,
  school_name                TEXT,
  scheduled_at               TIMESTAMPTZ NOT NULL,
  duration_minutes           INTEGER NOT NULL DEFAULT 45,
  tier                       TEXT NOT NULL DEFAULT 'guided',
  status                     TEXT NOT NULL DEFAULT 'pending_payment',
  amount_cents               INTEGER,
  waived                     BOOLEAN NOT NULL DEFAULT false,
  coupon_code                TEXT,
  stripe_checkout_session_id TEXT,
  stripe_payment_intent_id   TEXT,
  zoom_join_url              TEXT,
  zoom_meeting_id            TEXT,
  prep_status                JSONB NOT NULL DEFAULT '{}'::jsonb,
  source                     TEXT,
  specialist_notified_at     TIMESTAMPTZ,
  reminder_sent_at           TIMESTAMPTZ,
  notes                      TEXT,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  parent_booking_id          UUID,                                        -- -> onboarding_bookings.id
  session_number             INTEGER NOT NULL DEFAULT 1,
  sms_consent                BOOLEAN NOT NULL DEFAULT false,
  sms_consent_at             TIMESTAMPTZ
);

CREATE TABLE onboarding_checklist_items (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sort_order INTEGER NOT NULL DEFAULT 0,
  section    TEXT NOT NULL DEFAULT 'On the call',
  label      TEXT NOT NULL,
  detail     TEXT,
  active     BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE prospect_schools (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  school_name            TEXT,
  owner_name             TEXT,
  email                  TEXT,
  phone                  TEXT,
  city                   TEXT,
  state                  TEXT,
  website                TEXT,
  status                 TEXT NOT NULL DEFAULT 'lead',
  assigned_specialist_id UUID,                                        -- -> onboarding_specialists.id
  notes                  TEXT,
  linked_booking_id      UUID,                                        -- -> onboarding_bookings.id
  converted_at           TIMESTAMPTZ,
  source                 TEXT DEFAULT 'import',
  raw                    JSONB,
  imported_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  email_norm             TEXT,
  phone_norm             TEXT,
  email_opted_out        BOOLEAN NOT NULL DEFAULT false,
  email_opted_out_at     TIMESTAMPTZ,
  unsubscribe_token      UUID NOT NULL DEFAULT gen_random_uuid(),
  last_emailed_at        TIMESTAMPTZ,
  email_count            INTEGER NOT NULL DEFAULT 0,
  style                  TEXT,
  years_operating        INTEGER,
  student_count          INTEGER,
  current_software       TEXT,
  accreditation_status   TEXT NOT NULL DEFAULT 'not_started',
  accredited_at          TIMESTAMPTZ,
  grace_period_ends_at   DATE,
  member_school_id       UUID                                         -- -> schools.id
);

CREATE TABLE prospect_emails (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prospect_id UUID,                                        -- -> prospect_schools.id
  to_email    TEXT,
  subject     TEXT,
  template    TEXT,
  status      TEXT NOT NULL DEFAULT 'sent',
  resend_id   TEXT,
  error       TEXT,
  sent_by     UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE prospect_accreditation (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prospect_id    UUID NOT NULL,                               -- -> prospect_schools.id
  requirement_id UUID NOT NULL,                               -- -> accreditation_requirements.id
  status         TEXT NOT NULL DEFAULT 'needed',
  answer         TEXT,
  file_path      TEXT,
  file_name      TEXT,
  notes          TEXT,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE accreditation_requirements (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  standard       INTEGER NOT NULL,
  standard_label TEXT NOT NULL,
  label          TEXT NOT NULL,
  detail         TEXT,
  field_type     TEXT NOT NULL DEFAULT 'file',
  choices        TEXT[],
  phase          TEXT NOT NULL DEFAULT 'collect_now',
  sort_order     INTEGER NOT NULL DEFAULT 0,
  active         BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------------------
--  BACKUP / SNAPSHOT
--  One-off snapshot table from a prior migration. Not part of the live
--  data path; audit before relying on or dropping.
-- -------------------------------------------------------------------------

CREATE TABLE bucket_state_backup (
  id                     UUID,
  school_id              UUID,         -- -> schools.id
  student_id             UUID,         -- -> students.id
  membership_id          UUID,         -- -> memberships.id
  program_id             UUID,         -- -> programs.id
  status                 TEXT,
  start_date             DATE,
  created_at             TIMESTAMPTZ,
  stripe_subscription_id TEXT,
  last_payment_at        TIMESTAMPTZ,
  ended_at               TIMESTAMPTZ,
  started_at             TIMESTAMPTZ,
  classes_used           INTEGER,
  expires_at             TIMESTAMPTZ,
  cycle_start_date       DATE,
  cycle_end_date         DATE,
  cycle_allowance        INTEGER,
  classes_remaining      INTEGER,
  rollover_balance       INTEGER,
  snapshot_taken_at      TIMESTAMPTZ
);

-- ===========================================================================
--  KNOWN DRIFT & GOTCHAS  (carry-forward notes, not DDL)
-- ===========================================================================
--  * students.membership_id / .plan_type / .membership_status are LEGACY
--    pointers. student_memberships is canonical. MRR / belt eligibility /
--    profile vitals must resolve through the junction, not these columns.
--  * class packs vs session packs are separate flows:
--      - class packs ride student_memberships (is_class_pack=true);
--        classes_remaining is decremented ONLY by the DB trigger
--        handle_attendance_deduction on class_attendance insert.
--      - session packs ride student_session_packs (pack_kind); deducted on
--        sessions status flip.
--  * payments is the canonical money ledger (NOT the old
--    billing_transactions from the genesis schema, which no longer
--    exists). amount_paid is
--    canonical on event_registrations (amount is legacy/redundant).
--  * Stripe = direct charges on connected accounts. Card storage:
--    students.stripe_connected_customer_id (on the school's connected acct);
--    schools.stripe_account_id is the connected account. The platform
--    subscription uses schools.stripe_customer_id / stripe_subscription_id.
--  * Pricing is flat ($99/mo + 1% fee, cap schools.platform_fee_cap_cents=
--    20000). school_subscription_tiers is a tiering scaffold that exists but
--    is not what the locked flat pricing uses -- confirm before building on it.
--  * event_registrations has redundant legacy cols (name/email/phone vs
--    guest_*; amount vs amount_paid) flagged for cleanup.
--  * bucket_state_backup is a migration snapshot, not live.
--  * Ordinal gaps (e.g. schools has no pos 65, sessions no pos 9, students
--    no pos 21) are dropped columns -- expected, not an export error.
-- ===========================================================================
