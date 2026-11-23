-- LOGOS staging student profile import extension.
-- Safe to apply only to logos-student-platform-staging.
-- Adds nullable legacy profile fields without weakening existing RLS or changing existing columns.
begin;

alter table public.students
  add column if not exists app_student_id text,
  add column if not exists gender text,
  add column if not exists department text,
  add column if not exists exam_type text,
  add column if not exists fee_amount numeric(12,2),
  add column if not exists app_created_on date,
  add column if not exists enrollment_month text,
  add column if not exists photo_storage_path text,
  add column if not exists legacy_metadata jsonb not null default '{}'::jsonb;

create unique index if not exists students_app_student_id_uidx
  on public.students (app_student_id)
  where app_student_id is not null;

comment on column public.students.app_student_id is
  'Stable identifier from the legacy LOGOS Android app; used for idempotent staging imports.';
comment on column public.students.fee_amount is
  'Legacy fee value copied from Android backup. Do not use for balances until currency and meaning are confirmed.';
comment on column public.students.enrollment_month is
  'Legacy Android start month in YYYY-MM form; distinct from academic_session.';
comment on column public.students.photo_storage_path is
  'Path to a private Storage object; never store base64 photo data in this column.';
comment on column public.students.legacy_metadata is
  'Unclassified legacy fields retained during migration review; never expose in student-facing queries.';

commit;
