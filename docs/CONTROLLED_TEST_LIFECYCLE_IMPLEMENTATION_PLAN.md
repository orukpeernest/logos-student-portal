# Controlled Test Driller: server lifecycle implementation plan

Status: design checkpoint only. This document does not apply database changes or deploy code.

## Confirmed current branch behavior

- The administrator can upload a JSON question file directly into a newly created draft assessment.
- The upload parser forces each imported question to `is_practice: false`; questions are saved and attached to the draft assessment in order.
- Students have an explicit **UPDATE TEST QUESTIONS** action. It retrieves released assessments and their questions.
- The current student start flow still calls `logos_td_student_exam_questions` directly and creates a client-side UUID. It does not create a server-side attempt before the timer starts.
- The countdown is browser-controlled. On expiry it calls the existing submit RPC.
- The current submit RPC stores summary counts only; individual selected answers are not persisted.
- The results RPC returns summary attempt fields only.
- No `pg_cron` or `pg_net` extension was returned by the supplied read-only inspection.

## Required lifecycle

`Draft -> Released -> Started -> Submitted / Auto-submitted`

1. Admin creates an assessment and directly uploads its own question file. No picking questions from the practice bank.
2. Admin configures assessment period (weekly/monthly), duration, start time and end/availability time.
3. Draft questions remain inaccessible to students. Admin release is an explicit action.
4. Student presses **UPDATE TEST QUESTIONS** to retrieve released tests.
5. Student starts a test. A server RPC creates or returns the permitted attempt and records `started_at` and authoritative `expires_at`.
6. Answers are saved as the student works. Reloading the page must recover the same active attempt and remaining server time.
7. Every answer-save and submit RPC checks the server timestamp against `expires_at`; browser time is never authoritative.
8. At expiry, a server-side scheduled worker finalizes expired attempts. If no scheduler is available, the application must clearly report that true unattended auto-finalization is not configured; submit-on-resume alone is not equivalent.
9. Submission stores each question's selected answer (including blank), correctness, and stable question reference/snapshot as appropriate, plus attempt totals.
10. `unanswered_count` remains a separately displayed count. Per the requested marking rule, unanswered questions are included in the overall wrong count: `wrong_count = total_questions - correct_count`. If an answered-wrong subtotal is displayed, it is `total - correct - unanswered`; do not add that subtotal to wrong_count.
11. Student and admin result visibility remains controlled by administrator release settings.

## Confirmed database facts and migration constraints

Existing tables:
- `logos_td_exams`: id, title, subject, exam_type, duration_minutes, status, released_at, created_at.
- `logos_td_exam_questions`: exam_id, question_id, position.
- `logos_td_questions`: question text/options/correct answer/explanation/image and `is_practice`.
- `logos_td_attempts`: summary score/counts, duration_seconds, submitted_at (currently NOT NULL with default now()).

Existing RPC facts:
- Student identity is derived from `auth.uid()` and `students.auth_user_id`; preserve this.
- Test question RPC withholds correct answers/explanations; preserve this.
- Submission validates the released exam and attached question IDs, calculates the score, and is idempotent by student/client_attempt_id.
- Submission currently trusts client duration and does not persist individual answers.
- Current wrong_count excludes unanswered; this differs from the requested reporting rule.
- Existing result RPC returns summary-only data.

Migration must be additive and preserve historic submitted attempts. Before writing executable SQL, inspect all existing constraints, indexes, triggers, grants, and the complete definitions of the create/release/question/submit/result RPCs. In particular, verify the unique key used for attempt idempotency and all existing exam_type/status constraints. Do not change existing rows to in-progress or rewrite their submitted timestamps.

## Required backend additions

- Assessment availability fields for start/end timestamps and the weekly/monthly period, with validation and timezone-aware storage.
- Attempt lifecycle fields: status, started_at, expires_at, submitted_at semantics. Existing attempts must remain submitted.
- An attempt-answer table keyed uniquely by attempt and exam question, storing selected answer (blank/null for unanswered), correctness, and a stable question reference or snapshot.
- A server-authoritative start/retrieve RPC, save-answer RPC, and idempotent submit/finalize RPC.
- A scheduler/worker that finds expired in-progress attempts and invokes the same safe finalization logic. Scheduler choice must be confirmed from actual deployment capabilities; do not assume an extension exists.
- Results RPC updates that expose only information allowed by admin result-release policy.
- A transactional bulk-upload RPC is now included in the migration and used by the admin UI. Verify rollback behavior in staging before production.

## Frontend changes after backend contract is fixed

- Replace the client-generated attempt lifecycle with start/retrieve RPC.
- Restore in-progress attempt and server expiry after refresh.
- Persist answer changes through the save-answer RPC (with safe debouncing/serialization).
- Keep the countdown as a display of server expiry, and submit when the server says the attempt is expired.
- Prevent leaving/restarting from silently creating a second attempt; follow the configured attempt limit.
- Display unanswered count and wrong count with clear wording that unanswered is included in wrong.
- Add result-detail review only after the backend stores answer records and the admin permits result visibility.

## Acceptance tests

- A draft assessment and its questions are invisible to students.
- Release makes the assessment available; UPDATE TEST QUESTIONS retrieves it.
- A Test Mode upload creates exam-only questions and never changes the practice bank.
- An upload error leaves the assessment as draft and reports exactly how many questions were attached.
- Starting an assessment creates one server-side attempt with a server timestamp and expiry.
- Refreshing/reopening restores the same attempt and its remaining time.
- A client cannot extend time by changing its clock or submitted duration.
- Answers persist individually; blanks are preserved.
- At expiry, the scheduler finalizes the attempt even if the student is offline.
- Repeated submit requests return the same final result without duplicate attempts.
- Correct + answered-wrong + unanswered equals total; wrong_count equals answered-wrong + unanswered.
- Historical attempts remain readable and unchanged.
- Students cannot see answers/results before the administrator's configured release.


## Additional facts confirmed from the latest database and frontend inspection

### Constraints and indexes to preserve

- `logos_td_attempts_student_id_client_attempt_id_key` uniquely enforces one record per student/client attempt ID.
- `logos_td_attempts_exam_id_fkey` is RESTRICT; an exam with historical attempts cannot be deleted.
- `logos_td_exam_questions` has primary key (exam_id, question_id) and unique (exam_id, position).
- `logos_td_exam_questions_question_id_fkey` is RESTRICT; attached questions cannot be deleted.
- Exam status is constrained to draft/released/closed.
- Exam duration must be positive.
- Exam and question subject are constrained to: English, Mathematics, Physics, Chemistry, Biology, Government, CRS, Literature, Economics, Commerce.
- Question correct_answer is constrained to A/B/C/D.
- Existing indexes include attempt lookup by exam/student, exam status/released_at, and question practice/subject indexes. Do not drop or rename these as part of the upgrade.

### Confirmed current administrator upload implementation

- Admin uploads a JSON file (maximum 10 MB, maximum 500 questions).
- The browser validates the file and forces `is_practice=false`.
- It creates a draft using `logos_td_admin_create_exam`, then sequentially saves each question and attaches it using `logos_td_admin_attach_question`.
- This is not one database transaction. If a later question fails, the draft remains with the already attached subset. The UI reports the draft ID and attached count and instructs the admin not to release it.
- The current form includes title, subject, Weekly/Monthly period, duration and question file.
- It does NOT yet include a start date/time, end/closing date/time, academic session, or result-release control.
- Release is separate through the admin status form. The current release RPC checks that at least one attached question exists and all attached questions are exam-only.
- The generic single-question editor and exam attach form remain present; they are separate admin functions and do not change the agreed direct-upload workflow.

### Confirmed current student workflow limitations

- The UPDATE TEST QUESTIONS button is implemented and retrieves released exams and question lists.
- Starting an exam still calls the public released-question RPC directly, creates a UUID in the browser, and starts a browser-only countdown.
- The existing question RPC can be called repeatedly for any released exam and has no server-side attempt/session gate.
- The current browser timer submits only when the page is running. It cannot guarantee unattended auto-submission after the student closes the browser.
- The existing submit function stores no per-question answer rows and trusts the browser-supplied duration.
- The existing results RPC exposes summary results immediately; there is no confirmed admin-controlled result-release field in the inspected schema/function set.

### Additional migration safety requirement

The latest SQL output did not include the definition of `logos_td_admin_save_question`, nor the function ACLs and RLS/grants for any future attempt-answer table. Before generating the final executable migration, inspect that function and the relevant grants. New answer rows must remain inaccessible through direct table access and be exposed only through authenticated, identity-checked RPCs. Do not add broad authenticated SELECT/INSERT policies to the answer table.

### Scheduler decision

The project currently has neither `pg_cron` nor `pg_net` installed. Do not install an extension or assume a scheduled worker is available. The implementation needs a separately deployed server-side worker (for example, a Supabase Edge Function invoked by a trusted scheduler) with a secret held only server-side. The worker must call a narrowly scoped finalization routine that finds and finalizes expired attempts. A client-callable function must never be allowed to finalize other students' attempts. Production acceptance requires proof that the scheduler actually runs while the student is offline.
