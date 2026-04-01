-- ═══════════════════════════════════════════════════════════════
--  NMAO PLATFORM — COMPLETE DATABASE SCHEMA
--  Paste this entire file into Supabase SQL Editor and run.
--  All tables, relationships, RLS policies, and seed data included.
-- ═══════════════════════════════════════════════════════════════

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─────────────────────────────────────────────
--  1. SCHOOLS (root entity — one per school owner)
-- ─────────────────────────────────────────────
CREATE TABLE schools (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name            TEXT NOT NULL,
  slug            TEXT UNIQUE NOT NULL,          -- URL-friendly name: "dragon-arts-academy"
  owner_id        UUID NOT NULL,                 -- references auth.users
  email           TEXT NOT NULL,
  phone           TEXT,
  address         TEXT,
  logo_url        TEXT,
  color           TEXT DEFAULT '#e8273a',        -- school accent color
  -- NMAO Accreditation fields
  nmao_accred_status TEXT DEFAULT 'pending' CHECK (nmao_accred_status IN ('pending','accredited','expired','suspended')),
  nmao_accred_score  INTEGER DEFAULT 0,          -- 0–9 standards met
  nmao_accred_expiry DATE,
  -- Stripe
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  plan_tier       TEXT DEFAULT 'foundation' CHECK (plan_tier IN ('foundation','school_pro','multi_location')),
  -- Meta
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
--  2. NMAO ACCREDITATION STANDARDS
-- ─────────────────────────────────────────────
CREATE TABLE nmao_standards (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  standard_name   TEXT NOT NULL,
  status          TEXT DEFAULT 'pending' CHECK (status IN ('met','in_progress','pending')),
  evidence_url    TEXT,                          -- uploaded PDF/image
  notes           TEXT,
  last_reviewed   TIMESTAMPTZ,
  reviewed_by     TEXT,                          -- NMAO admin name
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
--  3. PROGRAMS
-- ─────────────────────────────────────────────
CREATE TABLE programs (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  description     TEXT,
  age_group       TEXT,
  age_group_label TEXT DEFAULT 'Age Group',      -- white-label field name
  belt_system     TEXT,
  color           TEXT DEFAULT '#e8273a',
  monthly_fee     NUMERIC(10,2) DEFAULT 0,
  sort_order      INTEGER DEFAULT 0,
  active          BOOLEAN DEFAULT TRUE,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
--  4. AGE GROUP OPTIONS (per school, white-labeled)
-- ─────────────────────────────────────────────
CREATE TABLE age_group_options (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  label           TEXT NOT NULL,
  sort_order      INTEGER DEFAULT 0
);

-- ─────────────────────────────────────────────
--  5. MEMBERSHIPS
-- ─────────────────────────────────────────────
CREATE TABLE memberships (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  program_id      UUID NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  billing_type    TEXT DEFAULT 'monthly' CHECK (billing_type IN ('monthly','yearly','trial','custom')),
  price           NUMERIC(10,2) NOT NULL DEFAULT 0,
  trial_days      INTEGER DEFAULT 0,
  start_date      DATE,
  autopay         BOOLEAN DEFAULT TRUE,
  pause_allowed   BOOLEAN DEFAULT FALSE,
  stripe_price_id TEXT,                          -- Stripe Price ID (set after Stripe setup)
  active          BOOLEAN DEFAULT TRUE,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
--  6. CLASS PACKS
-- ─────────────────────────────────────────────
CREATE TABLE class_packs (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  program_id      UUID NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  class_quantity  INTEGER NOT NULL DEFAULT 10,
  expiry_days     INTEGER DEFAULT 60,            -- 0 = no expiry
  price           NUMERIC(10,2) NOT NULL DEFAULT 0,
  stripe_price_id TEXT,
  active          BOOLEAN DEFAULT TRUE,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
--  7. CLASSES
-- ─────────────────────────────────────────────
CREATE TABLE classes (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  program_id      UUID NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
  instructor_id   UUID REFERENCES instructors(id) ON DELETE SET NULL, -- defined below
  name            TEXT NOT NULL,
  description     TEXT,
  schedule        TEXT,                          -- "Mon/Wed/Fri 6:00 PM"
  duration_minutes INTEGER DEFAULT 60,
  capacity        INTEGER DEFAULT 18,
  enrolled_count  INTEGER DEFAULT 0,
  wkc_prep        BOOLEAN DEFAULT FALSE,         -- tag as WKC competition prep class
  active          BOOLEAN DEFAULT TRUE,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Class ↔ Membership access (many-to-many)
CREATE TABLE class_membership_access (
  class_id        UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  membership_id   UUID NOT NULL REFERENCES memberships(id) ON DELETE CASCADE,
  PRIMARY KEY (class_id, membership_id)
);

-- Class ↔ Class Pack access (many-to-many)
CREATE TABLE class_pack_access (
  class_id        UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  class_pack_id   UUID NOT NULL REFERENCES class_packs(id) ON DELETE CASCADE,
  PRIMARY KEY (class_id, class_pack_id)
);

-- ─────────────────────────────────────────────
--  8. FAMILIES (parent accounts)
-- ─────────────────────────────────────────────
CREATE TABLE families (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  guardian_name   TEXT NOT NULL,
  email           TEXT NOT NULL,
  phone           TEXT,
  stripe_customer_id TEXT,                       -- one Stripe customer per family
  user_id         UUID,                          -- references auth.users (family portal login)
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
--  9. STUDENTS
-- ─────────────────────────────────────────────
CREATE TABLE students (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  family_id       UUID REFERENCES families(id) ON DELETE SET NULL,
  program_id      UUID REFERENCES programs(id) ON DELETE SET NULL,
  first_name      TEXT NOT NULL,
  last_name       TEXT NOT NULL,
  initials        TEXT GENERATED ALWAYS AS (UPPER(LEFT(first_name,1) || LEFT(last_name,1))) STORED,
  date_of_birth   DATE,
  email           TEXT,
  phone           TEXT,
  -- Belt & progression
  current_belt    TEXT DEFAULT 'white' CHECK (current_belt IN ('white','yellow','orange','green','blue','purple','red','brown','black')),
  skills_completed INTEGER DEFAULT 0,
  skills_total    INTEGER DEFAULT 8,
  -- Plan
  plan_type       TEXT CHECK (plan_type IN ('membership','class_pack')),
  membership_id   UUID REFERENCES memberships(id) ON DELETE SET NULL,
  class_pack_id   UUID REFERENCES class_packs(id) ON DELETE SET NULL,
  pack_classes_remaining INTEGER,
  -- Status
  status          TEXT DEFAULT 'trial' CHECK (status IN ('active','trial','paused','expired','cancelled')),
  waiver_signed   BOOLEAN DEFAULT FALSE,
  waiver_signed_at TIMESTAMPTZ,
  -- Stripe
  stripe_subscription_id TEXT,
  -- Meta
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Student ↔ Class enrollment (many-to-many)
CREATE TABLE student_class_enrollments (
  student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  class_id        UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  enrolled_at     TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (student_id, class_id)
);

-- ─────────────────────────────────────────────
--  10. BELT SKILL CHECKLIST
-- ─────────────────────────────────────────────
CREATE TABLE belt_skills (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  program_id      UUID NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
  belt_level      TEXT NOT NULL,
  skill_name      TEXT NOT NULL,
  description     TEXT,
  sort_order      INTEGER DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Student skill sign-offs
CREATE TABLE student_skill_signoffs (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  skill_id        UUID NOT NULL REFERENCES belt_skills(id) ON DELETE CASCADE,
  signed_off_by   UUID,                          -- instructor user_id
  signed_off_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (student_id, skill_id)
);

-- ─────────────────────────────────────────────
--  11. BELT PROMOTION HISTORY (immutable log)
-- ─────────────────────────────────────────────
CREATE TABLE belt_promotions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  belt_from       TEXT NOT NULL,
  belt_to         TEXT NOT NULL,
  promoted_at     TIMESTAMPTZ DEFAULT NOW(),
  promoted_by     UUID,                          -- instructor user_id
  promoted_by_name TEXT,
  ceremony_date   DATE,
  notes           TEXT
);

-- ─────────────────────────────────────────────
--  12. INSTRUCTORS
-- ─────────────────────────────────────────────
CREATE TABLE instructors (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  user_id         UUID,                          -- auth.users (staff login)
  name            TEXT NOT NULL,
  email           TEXT,
  phone           TEXT,
  title           TEXT,                          -- "Sensei", "Coach", "Professor"
  bio             TEXT,
  photo_url       TEXT,
  -- NMAO certification
  nmao_cert_status TEXT DEFAULT 'uncertified' CHECK (nmao_cert_status IN ('certified','pending','uncertified','expired')),
  nmao_cert_expiry DATE,
  nmao_cert_level TEXT,
  -- Role
  role            TEXT DEFAULT 'instructor' CHECK (role IN ('owner','head_instructor','instructor','assistant')),
  active          BOOLEAN DEFAULT TRUE,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Fix forward reference: add instructor_id FK to classes now that instructors table exists
ALTER TABLE classes ADD CONSTRAINT classes_instructor_fk
  FOREIGN KEY (instructor_id) REFERENCES instructors(id) ON DELETE SET NULL;

-- ─────────────────────────────────────────────
--  13. ATTENDANCE
-- ─────────────────────────────────────────────
CREATE TABLE attendance (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  class_id        UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  checked_in_at   TIMESTAMPTZ DEFAULT NOW(),
  method          TEXT DEFAULT 'kiosk' CHECK (method IN ('kiosk','staff','app','manual'))
);

CREATE INDEX attendance_student_idx ON attendance(student_id);
CREATE INDEX attendance_class_idx ON attendance(class_id);
CREATE INDEX attendance_date_idx ON attendance(checked_in_at);

-- ─────────────────────────────────────────────
--  14. LEADS (CRM pipeline)
-- ─────────────────────────────────────────────
CREATE TABLE leads (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  email           TEXT,
  phone           TEXT,
  source          TEXT DEFAULT 'website' CHECK (source IN ('website','referral','walk_in','social','wkc','other')),
  status          TEXT DEFAULT 'new' CHECK (status IN ('new','contacted','trial_booked','enrolled','lost')),
  program_interest UUID REFERENCES programs(id) ON DELETE SET NULL,
  trial_class_id  UUID REFERENCES classes(id) ON DELETE SET NULL,
  trial_date      DATE,
  notes           TEXT,
  converted_student_id UUID REFERENCES students(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
--  15. WKC COMPETITION
-- ─────────────────────────────────────────────
CREATE TABLE wkc_events (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name            TEXT NOT NULL,
  event_date      DATE NOT NULL,
  location        TEXT,
  registration_deadline DATE,
  status          TEXT DEFAULT 'upcoming' CHECK (status IN ('upcoming','open','closed','completed')),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE wkc_registrations (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  event_id        UUID NOT NULL REFERENCES wkc_events(id) ON DELETE CASCADE,
  division        TEXT NOT NULL,                 -- "Beginner", "Intermediate", "Advanced"
  event_category  TEXT,                          -- "Open Traditional Kata", "Open Creative Kata", etc.
  result_placement INTEGER,                      -- 1=Gold, 2=Silver, 3=Bronze, 4–10, etc.
  points_earned   INTEGER DEFAULT 0,
  registered_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (student_id, event_id, event_category)
);

-- WKC points formula trigger
CREATE OR REPLACE FUNCTION calculate_wkc_points()
RETURNS TRIGGER AS $$
BEGIN
  NEW.points_earned := CASE
    WHEN NEW.result_placement = 1 THEN 100
    WHEN NEW.result_placement = 2 THEN 80
    WHEN NEW.result_placement = 3 THEN 60
    WHEN NEW.result_placement BETWEEN 4 AND 7 THEN 45
    WHEN NEW.result_placement BETWEEN 8 AND 10 THEN 35
    ELSE 25
  END;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER wkc_points_trigger
  BEFORE INSERT OR UPDATE ON wkc_registrations
  FOR EACH ROW EXECUTE FUNCTION calculate_wkc_points();

-- ─────────────────────────────────────────────
--  16. BILLING TRANSACTIONS (for reporting)
-- ─────────────────────────────────────────────
CREATE TABLE billing_transactions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  student_id      UUID REFERENCES students(id) ON DELETE SET NULL,
  family_id       UUID REFERENCES families(id) ON DELETE SET NULL,
  amount          NUMERIC(10,2) NOT NULL,
  currency        TEXT DEFAULT 'usd',
  status          TEXT DEFAULT 'pending' CHECK (status IN ('pending','succeeded','failed','refunded')),
  stripe_payment_intent_id TEXT,
  stripe_invoice_id TEXT,
  description     TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
--  17. NOTIFICATIONS / ALERTS
-- ─────────────────────────────────────────────
CREATE TABLE notifications (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  recipient_type  TEXT CHECK (recipient_type IN ('owner','instructor','student','parent')),
  recipient_id    UUID,
  type            TEXT NOT NULL,                 -- 'belt_ready','payment_failed','membership_expiring', etc.
  title           TEXT NOT NULL,
  body            TEXT,
  read            BOOLEAN DEFAULT FALSE,
  sent_email      BOOLEAN DEFAULT FALSE,
  sent_sms        BOOLEAN DEFAULT FALSE,
  related_student_id UUID REFERENCES students(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────
--  ROW LEVEL SECURITY (RLS)
--  Schools can only see their own data.
-- ─────────────────────────────────────────────
ALTER TABLE schools ENABLE ROW LEVEL SECURITY;
ALTER TABLE programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE class_packs ENABLE ROW LEVEL SECURITY;
ALTER TABLE classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE families ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE belt_promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE wkc_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE nmao_standards ENABLE ROW LEVEL SECURITY;
ALTER TABLE instructors ENABLE ROW LEVEL SECURITY;

-- School owners see their own school
CREATE POLICY school_owner_policy ON schools
  FOR ALL USING (owner_id = auth.uid());

-- Generic "school member" policy for all sub-tables
CREATE OR REPLACE FUNCTION school_id_policy(table_school_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM schools WHERE id = table_school_id AND owner_id = auth.uid()
  );
$$ LANGUAGE sql SECURITY DEFINER;

CREATE POLICY programs_policy ON programs FOR ALL USING (school_id_policy(school_id));
CREATE POLICY memberships_policy ON memberships FOR ALL USING (school_id_policy(school_id));
CREATE POLICY class_packs_policy ON class_packs FOR ALL USING (school_id_policy(school_id));
CREATE POLICY classes_policy ON classes FOR ALL USING (school_id_policy(school_id));
CREATE POLICY students_policy ON students FOR ALL USING (school_id_policy(school_id));
CREATE POLICY families_policy ON families FOR ALL USING (school_id_policy(school_id));
CREATE POLICY attendance_policy ON attendance FOR ALL USING (school_id_policy(school_id));
CREATE POLICY leads_policy ON leads FOR ALL USING (school_id_policy(school_id));
CREATE POLICY belt_promo_policy ON belt_promotions FOR ALL USING (school_id_policy(school_id));
CREATE POLICY notifications_policy ON notifications FOR ALL USING (school_id_policy(school_id));
CREATE POLICY wkc_reg_policy ON wkc_registrations FOR ALL USING (school_id_policy(school_id));
CREATE POLICY billing_policy ON billing_transactions FOR ALL USING (school_id_policy(school_id));
CREATE POLICY nmao_policy ON nmao_standards FOR ALL USING (school_id_policy(school_id));
CREATE POLICY instructors_policy ON instructors FOR ALL USING (school_id_policy(school_id));

-- ─────────────────────────────────────────────
--  UPDATED_AT TRIGGERS
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER schools_updated_at BEFORE UPDATE ON schools FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER programs_updated_at BEFORE UPDATE ON programs FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER memberships_updated_at BEFORE UPDATE ON memberships FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER class_packs_updated_at BEFORE UPDATE ON class_packs FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER classes_updated_at BEFORE UPDATE ON classes FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER students_updated_at BEFORE UPDATE ON students FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER families_updated_at BEFORE UPDATE ON families FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER leads_updated_at BEFORE UPDATE ON leads FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─────────────────────────────────────────────
--  HELPFUL VIEWS
-- ─────────────────────────────────────────────

-- Monthly Recurring Revenue per school
CREATE OR REPLACE VIEW school_mrr AS
SELECT
  s.school_id,
  SUM(CASE
    WHEN m.billing_type = 'monthly' THEN m.price
    WHEN m.billing_type = 'yearly' THEN ROUND(m.price / 12, 2)
    ELSE 0
  END) AS mrr
FROM students s
JOIN memberships m ON s.membership_id = m.id
WHERE s.status = 'active' AND s.plan_type = 'membership'
GROUP BY s.school_id;

-- Students with belt promotion readiness
CREATE OR REPLACE VIEW promotion_ready_students AS
SELECT
  s.id, s.school_id, s.first_name, s.last_name, s.initials,
  s.current_belt, s.skills_completed, s.skills_total,
  s.program_id,
  p.name AS program_name
FROM students s
JOIN programs p ON s.program_id = p.id
WHERE s.skills_completed >= s.skills_total
  AND s.current_belt != 'black'
  AND s.status IN ('active','trial');

-- Class fill rates
CREATE OR REPLACE VIEW class_fill_rates AS
SELECT
  c.id, c.school_id, c.name, c.capacity,
  c.enrolled_count,
  ROUND((c.enrolled_count::NUMERIC / NULLIF(c.capacity,0)) * 100, 1) AS fill_pct,
  p.name AS program_name, p.color AS program_color
FROM classes c
JOIN programs p ON c.program_id = p.id
WHERE c.active = TRUE;

-- ─────────────────────────────────────────────
--  DEFAULT NMAO STANDARDS (insert for each new school via trigger)
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION seed_nmao_standards()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO nmao_standards (school_id, standard_name, status) VALUES
    (NEW.id, 'Security', 'pending'),
    (NEW.id, 'Student Safety', 'pending'),
    (NEW.id, 'Emergency Preparedness', 'pending'),
    (NEW.id, 'Governance', 'pending'),
    (NEW.id, 'Financial Stability', 'pending'),
    (NEW.id, 'Continued Improvement', 'pending'),
    (NEW.id, 'Ethical Conduct', 'pending'),
    (NEW.id, 'Value to Students', 'pending'),
    (NEW.id, 'Commitment to Excellence', 'pending');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER seed_standards_on_school_create
  AFTER INSERT ON schools
  FOR EACH ROW EXECUTE FUNCTION seed_nmao_standards();

-- ─────────────────────────────────────────────
--  DEFAULT AGE GROUP OPTIONS (per school)
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION seed_age_group_options()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO age_group_options (school_id, label, sort_order) VALUES
    (NEW.id, 'Little Tigers (4–6)', 1),
    (NEW.id, 'Kids (7–12)', 2),
    (NEW.id, 'Teens (13–17)', 3),
    (NEW.id, 'Adults (18+)', 4),
    (NEW.id, 'All Ages', 5),
    (NEW.id, 'Seniors (55+)', 6);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER seed_age_options_on_school_create
  AFTER INSERT ON schools
  FOR EACH ROW EXECUTE FUNCTION seed_age_group_options();

-- ─────────────────────────────────────────────
--  WKC UPCOMING EVENTS (seed data)
-- ─────────────────────────────────────────────
INSERT INTO wkc_events (name, event_date, location, registration_deadline, status) VALUES
  ('WKC Spring Regional 2026', '2026-04-12', 'Los Angeles, CA', '2026-04-05', 'open'),
  ('WKC Summer Championships 2026', '2026-07-18', 'Chicago, IL', '2026-07-11', 'upcoming'),
  ('WKC Grand Championships 2026', '2026-11-08', 'Las Vegas, NV', '2026-11-01', 'upcoming');

-- ═══════════════════════════════════════════════════════════════
--  SCHEMA COMPLETE
--  Next steps:
--  1. Copy your Supabase Project URL and anon key to .env.local
--  2. Run: npx supabase gen types typescript --project-id YOUR_ID > types/supabase.ts
--  3. Add Stripe webhook to: /api/webhooks/stripe
-- ═══════════════════════════════════════════════════════════════
