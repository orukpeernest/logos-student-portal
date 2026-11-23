# Controlled Test Driller deployment and verification

This guide accompanies `supabase/migrations/202611230001_controlled_test_attempts.sql` and the `finalize-expired-tests` Edge Function.

## Important deployment boundary

The migration and application changes are committed to the development branch only. They have NOT been applied to the live Supabase project, and the Edge Function has NOT been deployed or scheduled. Do not merge to `main` or run the SQL until the migration has been reviewed and a current database backup exists.

## Deployment order

1. Schedule a maintenance window when no student is taking a live test. The migration revokes the old browser-side question-fetch and submission RPCs; deploying it while an old-version test is in progress could prevent that old client from submitting.
2. Take and verify a current Supabase database backup.
3. Review the SQL migration against the current live schema. Run it in a staging project first.
4. Deploy the Edge Function:
   `supabase functions deploy finalize-expired-tests --no-verify-jwt`
5. Set Edge Function secrets in Supabase:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `CRON_SECRET` (generate a long random value; do not commit it)
6. Configure a trusted external scheduler to POST to:
   `https://<project-ref>.supabase.co/functions/v1/finalize-expired-tests`
   Include header `x-cron-secret: <CRON_SECRET>`. Run at least once per minute for near-real-time expiry finalization.
7. Verify a successful worker response reports `ok: true` and a finalized count. Also verify an expired attempt is finalized while the student browser is closed.
8. Only then enable the updated student/admin frontend in the test environment.

The scheduler needs only the function endpoint and CRON_SECRET. The service-role key remains inside Supabase Edge Function secrets and is never sent to the scheduler or browser.

## RPC contract used by the updated frontend

- `logos_td_student_active_attempts()`: lists the authenticated student's active attempts so a closed assessment can still be found and resumed.
- `logos_td_student_start_exam(p_exam_id text)`: creates or resumes the student's server-timed attempt and returns attempt_id, started_at, expires_at, status and questions. Correct answers are not returned.
- `logos_td_student_save_exam_answer(p_attempt_id uuid, p_question_id text, p_selected_answer text)`: saves each answer; returns false if the deadline has already expired and the attempt was finalized.
- `logos_td_student_submit_exam_attempt(p_attempt_id uuid)`: submits the student's own attempt; repeated calls return the existing final result.
- `logos_td_student_attempt_detail(p_attempt_id uuid)`: returns per-question review only after results are released.
- `logos_td_admin_configure_exam(...)`: sets session, availability window and maximum attempts on a draft.
- `logos_td_admin_set_results_released(...)`: controls result visibility after release/closure.
- `logos_td_finalize_expired_attempts()`: service-role-only worker entry point.

The legacy student question-download and client-authoritative submit RPCs are revoked by the migration. The new frontend must be deployed only after the migration succeeds.

## Marking rules

- `unanswered_count` is the number of blank responses.
- `wrong_count = total_questions - correct_count`, so wrong includes unanswered.
- The separately displayed unanswered count is a subset of wrong; do not add it to wrong again.
- Score is correct answers divided by all questions, multiplied by 100.
- Per-question answers are snapshotted at attempt start so later edits to a question cannot change a submitted result.

## Known limitations to verify before production

- The assessment upload now calls a transactional bulk-upload RPC. If any question is invalid, the whole question batch rolls back and the assessment remains an empty draft. The draft must still remain unreleased until the admin verifies the upload.
- The current admin interface configures academic session, start/end availability, maximum attempts and results release, but it still needs full browser testing against the migrated database.
- The scheduler is not configured by this repository commit. Until it is actually deployed and observed finalizing attempts offline, unattended automatic submission is NOT production-verified.
- The old summary result function is updated to hide new results until the admin releases them. Historical exams keep the default visible setting.
- The new answer-detail review is gated by the assessment's `results_released` flag.

## Acceptance checklist

- Draft upload creates exam-only questions and leaves the practice bank unchanged.
- Draft questions are not visible to students.
- Release plus UPDATE TEST QUESTIONS makes an assessment appear.
- Start creates one attempt; reopening resumes it and does not reset the expiry.
- Attempt count is limited by the admin-configured maximum.
- Changing the device clock does not extend the server deadline.
- Each answer is persisted; blank answers remain blank.
- A student cannot save or submit another student's attempt.
- An expired attempt is finalized by the scheduler while the student is offline.
- Repeated submissions do not create duplicate attempts.
- Wrong count includes unanswered; unanswered remains separately visible.
- Students cannot see result summaries or answer keys until results are released.
- Existing historical attempt rows and submitted timestamps remain unchanged.
