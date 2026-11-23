# LOGOS student login implementation plan (STAGING ONLY)

## Scope
Implement student sign-in on the existing student portal using the agreed username format, with all work limited to the staging branch and staging Supabase project. Production must remain untouched.

## Credential format
- Source the suffix from the registration field (`reg`): strip non-digits and take the final four digits.
- Username: uppercase surname, remove spaces, append suffix.
- Initial password: suffix only (temporary bootstrap credential).
- Require the student to set a new password at first login.

## Current implementation gap
- The student portal currently accepts email/password and calls Supabase Auth `signInWithPassword`.
- The backup import validator only checks the backup locally; it does not import records or create auth users.
- Staging's foundation schema links `students.auth_user_id` to Supabase Auth users, but the backup's stable app ID and registration number need to be mapped into the portal schema without exposing the backup.

## Safe architecture
1. **Schema verification first:** Confirm the staging `students` columns and all student-facing RPCs, grants, and RLS. Do not infer a production schema.
2. **Server-side import:** Use a server-side privileged function/Edge Function (service-role secret stored only in Supabase secrets) to validate and transactionally upsert students by stable Android app ID. Return aggregate counts and sanitized validation issues only.
3. **Auth accounts:** Provision Supabase Auth accounts server-side using a deterministic internal email identifier derived from the validated username (not a student's real email). Never return a bulk credential list. Store the mapping/username in a unique database field/table, not in public client code.
4. **Login:** Prefer a server-side username lookup that resolves to the internal Auth identifier; client should never receive privileged credentials. If the Auth provider requires email/password, use the internal identifier behind the username login UI and validate collisions before provisioning.
5. **Initial password:** The four-digit value is bootstrap-only. Require a server-enforced first-login password change and block student-data RPC access until complete. A UI-only gate is insufficient.
6. **Rate limiting:** Add rate-limited login attempts, generic error messages, and no username enumeration.
7. **Student isolation:** Each student-facing RPC must resolve the linked student from `auth.uid()`; verify profile and all sensitive records are scoped. Shared question-bank RPCs may return shared practice content but only to authenticated, linked students.
8. **Testing:** Test only a dummy staging account first. Check login, forced password change, logout, dashboard, practice, released exam access, results, and cross-student denial. Use a real account only after these tests and safeguards are verified.

## Acceptance criteria
- No student backup or credential list committed to GitHub or returned to browser.
- No service-role key in static JavaScript.
- Duplicate usernames and missing/short registration suffixes fail closed.
- Import is transactional, admin-only, repeat-safe, and keyed by stable app student ID.
- First-login password change is enforced server-side.
- Login is rate-limited and does not reveal whether a username exists.
- Staging tests pass before any production plan.

## Current status
Read-only review only. No student data import, auth account creation, database/RLS changes, or production changes have been made.

## Progress update — 2026-11-24
- Created isolated branch `stage-2R40-staging-project-isolation`; production and the existing deployment branch remain untouched.
- Student and admin static portals now load a shared staging-only public configuration for project `rxuusshnsrpegwwktvii`. No production project reference remains in those portal files.
- Added staging configuration isolation tests and enabled the portal-check workflow on this branch. GitHub Actions run 86 completed successfully, including JavaScript syntax checks and all existing import / assessment security tests.
- Completed aggregate-only review of the Android backup and documented the field mapping in `docs/STAGING_STUDENT_BACKUP_FIELD_MAP.md`.
- No student records, photos, payment records, attendance records, or Auth accounts were imported or changed.

## Schema verification — 2026-11-24

- User applied migration `202611240001_student_profile_import_fields.sql` successfully in the staging project.
- Read-only verification returned all nine expected columns and types:
  - `app_student_id`, `gender`, `department`, `exam_type`, `enrollment_month`, `photo_storage_path`: text
  - `fee_amount`: numeric
  - `app_created_on`: date
  - `legacy_metadata`: jsonb, NOT NULL
- Academic session `2026/2027` was explicitly confirmed for all legacy profiles. Map it to `academic_session`; keep the legacy `start` month in `enrollment_month`.
- The legacy `fee` value remains unapproved for balance calculations until its currency and business meaning are confirmed.
- Existing student RLS remains enabled. The previously inspected policies permit administrators (via `is_logos_admin()`) to manage student rows and students to select only their linked row via `auth_user_id = auth.uid()`.
- No student data, photos, payment records, attendance records, or Auth accounts have been imported or changed.

## Next implementation gates

1. Complete read-only inspection of the current student table constraints, grants, relevant policies, admin authorization helper, and all existing student-facing RPCs on staging.
2. Build a server-side Edge Function for admin-authorized, bounded backup validation. It must authenticate the caller with their user JWT and independently verify administrator status; never trust a client-supplied admin flag.
3. Keep profile upsert transactional in a narrowly scoped database function, keyed by `app_student_id`, with collision checks for `student_code` and generated usernames. Preserve existing `auth_user_id` links and never overwrite unrelated fields.
4. Keep Auth account provisioning separate from profile import until username mapping, temporary-password handling, forced password change, rate limiting, and per-student access gates are implemented and tested. Auth Admin API operations cannot be assumed to share the database transaction.
5. Test with synthetic dummy records only. Return aggregate counts and sanitized issue codes; never return student rows, photos, generated credentials, or raw exception details.

The staging schema gate is complete; the importer and authentication gates remain open. Production and the Android app repositories remain out of scope.
