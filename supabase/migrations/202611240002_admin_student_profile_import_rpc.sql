-- LOGOS staging-only, admin-authorized, bounded student-profile import.
-- No Auth users, passwords, photos, payments, or attendance records are created/imported here.
-- The caller must use an authenticated Supabase session. The function independently checks admin membership.
begin;

create or replace function public.logos_admin_import_student_profiles(
  p_students jsonb,
  p_academic_session text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row jsonb;
  v_id text;
  v_reg text;
  v_surname text;
  v_first text;
  v_imported integer := 0;
  v_photo_pending integer := 0;
  v_fee numeric(12,2);
  v_created date;
  v_metadata jsonb;
begin
  if auth.uid() is null or not coalesce(public.is_logos_admin(), false) then
    raise exception 'Administrator authorization required.' using errcode = '42501';
  end if;

  if p_academic_session is distinct from '2026/2027' then
    raise exception 'Unsupported academic session.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_students) is distinct from 'array' then
    raise exception 'Import payload must be a JSON array.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_students) < 1
     or jsonb_array_length(p_students) > 100
     or pg_column_size(p_students) > 1048576 then
    raise exception 'Import must contain 1 to 100 profiles and remain within 1 MB.' using errcode = '22023';
  end if;

  -- Reject malformed records before writing any rows.
  for v_row in select value from jsonb_array_elements(p_students)
  loop
    if jsonb_typeof(v_row) is distinct from 'object'
       or coalesce(v_row->>'id','') = ''
       or length(v_row->>'id') > 64
       or coalesce(v_row->>'reg','') = ''
       or length(v_row->>'reg') > 64
       or coalesce(v_row->>'surname','') = ''
       or length(v_row->>'surname') > 100
       or coalesce(v_row->>'first','') = ''
       or length(v_row->>'first') > 100 then
      raise exception 'A profile is missing a required identifier or name, or exceeds a field limit.' using errcode = '22023';
    end if;

    if length(coalesce(v_row->>'other','')) > 100
       or length(coalesce(v_row->>'phone','')) > 32
       or length(coalesce(v_row->>'gphone','')) > 32
       or length(coalesce(v_row->>'gender','')) > 24
       or length(coalesce(v_row->>'dept','')) > 80
       or length(coalesce(v_row->>'exam','')) > 40 then
      raise exception 'A profile contains a value exceeding an allowed field limit.' using errcode = '22023';
    end if;

    if length(regexp_replace(coalesce(v_row->>'reg',''), '[^0-9]', '', 'g')) < 4 then
      raise exception 'A registration value does not contain four trailing digits.' using errcode = '22023';
    end if;

    if coalesce(v_row->>'start','') <> ''
       and (v_row->>'start') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
      raise exception 'An enrollment month has an invalid format.' using errcode = '22023';
    end if;

    if coalesce(v_row->>'added','') <> ''
       and (v_row->>'added') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'A profile creation date has an invalid format.' using errcode = '22023';
    end if;

    if coalesce(v_row->>'fee','') <> ''
       and (v_row->>'fee') !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' then
      raise exception 'A legacy fee value is invalid.' using errcode = '22023';
    end if;

    if length(coalesce(v_row->>'cycle','')) > 50
       or length(coalesce(v_row->>'dbase','')) > 100
       or length(coalesce(v_row->>'dstart','')) > 50
       or length(coalesce(v_row->>'expiry','')) > 50
       or length(coalesce(v_row->>'next','')) > 50 then
      raise exception 'Legacy metadata exceeds an allowed field limit.' using errcode = '22023';
    end if;
  end loop;

  -- Reject duplicate stable IDs, registration codes, and generated usernames within this batch.
  if exists (
    select 1 from jsonb_array_elements(p_students) x(value)
    group by x.value->>'id' having count(*) > 1
  ) or exists (
    select 1 from jsonb_array_elements(p_students) x(value)
    group by x.value->>'reg' having count(*) > 1
  ) or exists (
    select 1
    from jsonb_array_elements(p_students) x(value)
    group by
      regexp_replace(upper(trim(x.value->>'surname')), '\s+', '', 'g') ||
      right(regexp_replace(x.value->>'reg', '[^0-9]', '', 'g'), 4)
    having count(*) > 1
  ) then
    raise exception 'The import contains duplicate student identifiers or generated usernames.' using errcode = '23505';
  end if;

  -- Never silently merge a different legacy profile into an existing registration code.
  if exists (
    select 1
    from public.students s
    join jsonb_array_elements(p_students) x(value)
      on s.student_code = x.value->>'reg'
    where s.app_student_id is distinct from x.value->>'id'
  ) then
    raise exception 'A registration code is already assigned to a different profile.' using errcode = '23505';
  end if;

  -- All validation and collision checks complete. The loop is part of this transaction:
  -- any failure rolls back the entire batch.
  for v_row in select value from jsonb_array_elements(p_students)
  loop
    v_id := v_row->>'id';
    v_reg := v_row->>'reg';
    v_surname := trim(v_row->>'surname');
    v_first := trim(v_row->>'first');

    v_fee := null;
    if coalesce(v_row->>'fee','') <> '' then
      v_fee := (v_row->>'fee')::numeric(12,2);
    end if;
    v_created := null;
    if coalesce(v_row->>'added','') <> '' then
      v_created := (v_row->>'added')::date;
    end if;

    v_metadata := jsonb_strip_nulls(jsonb_build_object(
      'cycle', v_row->'cycle',
      'dbase', v_row->'dbase',
      'dstart', v_row->'dstart',
      'expiry', v_row->'expiry',
      'next', v_row->'next'
    ));

    insert into public.students (
      app_student_id, student_code, surname, first_name, other_names,
      phone, guardian_phone, academic_session, gender, department,
      exam_type, fee_amount, app_created_on, enrollment_month, legacy_metadata
    ) values (
      v_id, v_reg, v_surname, v_first, nullif(trim(coalesce(v_row->>'other','')), ''),
      nullif(trim(coalesce(v_row->>'phone','')), ''),
      nullif(trim(coalesce(v_row->>'gphone','')), ''),
      p_academic_session,
      nullif(trim(coalesce(v_row->>'gender','')), ''),
      nullif(trim(coalesce(v_row->>'dept','')), ''),
      nullif(trim(coalesce(v_row->>'exam','')), ''),
      v_fee, v_created, nullif(v_row->>'start',''), v_metadata
    )
    on conflict (app_student_id) where app_student_id is not null
    do update set
      student_code = excluded.student_code,
      surname = excluded.surname,
      first_name = excluded.first_name,
      other_names = coalesce(excluded.other_names, students.other_names),
      phone = coalesce(excluded.phone, students.phone),
      guardian_phone = coalesce(excluded.guardian_phone, students.guardian_phone),
      academic_session = excluded.academic_session,
      gender = coalesce(excluded.gender, students.gender),
      department = coalesce(excluded.department, students.department),
      exam_type = coalesce(excluded.exam_type, students.exam_type),
      fee_amount = coalesce(excluded.fee_amount, students.fee_amount),
      app_created_on = coalesce(excluded.app_created_on, students.app_created_on),
      enrollment_month = coalesce(excluded.enrollment_month, students.enrollment_month),
      legacy_metadata = students.legacy_metadata || excluded.legacy_metadata;

    v_imported := v_imported + 1;
    if coalesce(v_row->>'photo','') <> '' then
      v_photo_pending := v_photo_pending + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'imported', v_imported,
    'photos_deferred', v_photo_pending,
    'payments_imported', 0,
    'attendance_imported', 0,
    'auth_accounts_created', 0
  );
exception
  when insufficient_privilege then
    raise;
  when unique_violation then
    raise exception 'Import stopped because a student identifier conflicts with an existing profile.' using errcode = '23505';
  when invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'Import stopped because a profile contains an invalid date or numeric value.' using errcode = '22023';
end;
$function$;

revoke all on function public.logos_admin_import_student_profiles(jsonb, text) from public;
revoke all on function public.logos_admin_import_student_profiles(jsonb, text) from anon;
grant execute on function public.logos_admin_import_student_profiles(jsonb, text) to authenticated;

comment on function public.logos_admin_import_student_profiles(jsonb, text) is
  'Bounded, authenticated administrator-only transactional profile import. Does not create Auth users or import photos, payments, or attendance.';

commit;
