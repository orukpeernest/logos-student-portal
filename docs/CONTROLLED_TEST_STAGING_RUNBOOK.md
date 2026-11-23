# LOGOS TUTORIALS — controlled Test Driller staging runbook

This runbook is for an isolated Supabase staging project only. It is not permission to change production.

## 1. Safety boundary

- Keep the existing `logos-student-platform` project unchanged.
- Do not use production student, admin, payment, or authentication records in staging.
- Do not copy a production service-role key into browser code, GitHub files, chat, or a scheduler.
- Use a separate staging Supabase project with its own URL, database, Auth users, and secrets.
- Do not merge this development branch to `main` or enable the new frontend on production during staging.

## 2. Repository and branch

Repository: `orukpeernest/logos-student-portal`

Development branch: `stage-2R39-controlled-assessment-upload`

The controlled assessment work is committed to this branch. GitHub Actions must be green for the exact commit being tested.

## 3. Prepare isolated staging

1. Create a separate Supabase project named clearly as a LOGOS staging/test project.
2. Keep production credentials and data out of it.
3. In staging only, create one administrator Auth account and one student Auth account.
4. Record the staging project URL and project reference privately. Never paste secret keys into this repository.
5. Link the student account to a staging-only row in `public.students` using `auth_user_id`; add the administrator's Auth UUID to `public.admin_users`.

## 4. Apply SQL in this exact order

Use the staging project's Supabase Dashboard → SQL Editor. Confirm the project name is the staging project before running each script.

1. `docs/STAGING_TEST_DRILLER_FOUNDATION.sql`
   - Creates the isolated minimum Test Driller schema and fail-closed legacy RPC signatures.
   - Does not import real students or fees.
2. `supabase/migrations/202611230001_controlled_test_attempts.sql`
   - Adds server-timed attempts, per-question answer snapshots, guarded result release, and the expiry finalizer.
3. `docs/STAGING_RESTORE_ORIGINAL_SUPPORT_RPCS.sql`
   - Restores the current portal's required support RPCs while leaving legacy submission and question-download RPCs revoked.
4. `docs/CONTROLLED_TEST_STAGING_VERIFICATION.sql`
   - Read-only catalog and privilege verification.

Stop if any script errors. Do not skip a failed statement or continue to the next script. Capture the exact error message (without secrets) for review.

## 5. Database verification expectations

The read-only verification query should show:

- Required assessment and attempt lifecycle columns exist.
- `logos_td_attempt_answers` has RLS enabled.
- Browser roles cannot directly select or insert answer snapshots.
- Authenticated students can execute student lifecycle RPCs.
- Browser roles cannot execute the internal or scheduled expiry finalizer.
- Only `service_role` can execute the scheduled expiry finalizer.
- Every SECURITY DEFINER function uses an empty search path.

Catalog checks are necessary but not sufficient. Continue with the behavioural tests below.

## 6. Behavioural acceptance tests

Use only the staging administrator and student accounts.

| Test | Action | Expected result |
|---|---|---|
| Practice separation | Admin creates a practice question; student opens Practice Mode | It appears in Practice Mode with practice feedback. |
| Draft isolation | Admin creates a test draft and uploads test questions | Draft is not returned to student. Practice bank is unchanged. |
| Atomic upload | Attempt a batch containing one invalid question | Entire batch is rejected; no partial question set is attached. |
| Release and refresh | Admin releases a valid test; student selects UPDATE TEST QUESTIONS | Released test appears; draft tests remain hidden. |
| Start and resume | Student starts, leaves, then reopens the same test | Existing attempt resumes with the original server expiry. |
| Attempt limit | Student submits maximum permitted attempts and tries again | Further starts are rejected. |
| Answer persistence | Student selects answers and refreshes/reopens | Saved answers are restored. |
| Ownership | Try to access another staging student's attempt | Access is denied. |
| Deadline | Let an attempt expire | Server rejects late answer changes and finalizes the attempt. |
| Offline expiry | Close the student browser before expiry; let the scheduler run | Attempt is finalized without the browser being open. |
| Result gate | Student opens results before admin release | Result details remain hidden. |
| Result release | Admin releases results | Student can see score and review permitted question details. |
| Marking | Submit a mix of correct, wrong, and blank answers | Wrong includes blanks; unanswered is shown as a subset, not added twice. |
| Idempotency | Submit the same attempt more than once | Existing result is returned; no duplicate attempt is created. |

Record each test as PASS/FAIL with the staging commit SHA and date. Do not mark an untested item as passed.

## 7. Expiry worker setup

Only after the database migration and RPC verification pass:

1. Deploy `supabase/functions/finalize-expired-tests/index.ts` to the staging project.
2. Set these Edge Function secrets in staging:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `CRON_SECRET`
3. Configure a trusted scheduler to POST to the staging function endpoint at least once per minute with header `x-cron-secret`.
4. Keep the service-role key inside Supabase secrets. The scheduler receives only the cron secret and endpoint.
5. Confirm the worker reports `ok: true` and a finalized count.
6. Perform the offline-expiry acceptance test above.

The worker is not considered operational merely because its source code or static tests pass.

## 8. Frontend test

Only after the staging database checks pass, point a private test copy of the portal at staging credentials. Test the admin and student flows end-to-end. Never put a service-role key in frontend configuration.

The current repository's static checks do not replace browser testing against a real staging database.

## 9. Production gate

Production remains blocked until all of the following are true:

- Staging SQL scripts complete without errors.
- Database privilege and function checks meet the expected results.
- All behavioural acceptance tests pass.
- Expiry worker is deployed, scheduled, and proven to finalize an attempt while the browser is closed.
- Current production schema compatibility has been reviewed.
- A current production backup has been taken and verified.
- A maintenance window has been agreed.
- The user explicitly approves any production migration, deployment, or merge.

No production action is authorized by this runbook.
