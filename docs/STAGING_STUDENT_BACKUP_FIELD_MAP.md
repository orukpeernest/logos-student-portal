# LOGOS Android backup → staging student profile field map

**Status:** read-only mapping review complete. This document contains aggregate structure only; it contains no student names, registration numbers, contact details, photographs, or credentials.

## Backup inventory

- 52 student profiles
- 53 payment records
- 40 attendance records
- 0 expenditure records

The payment and attendance collections are deliberately outside the student-profile import. They require separate relationship and reconciliation checks before any migration.

## Student profile mapping

| Android backup field | Observed shape | Proposed destination | Decision |
|---|---|---|---|
| `id` | 14-character string; present on all 52 profiles | New `app_student_id` column, unique | Preserve as stable import/upsert key; do not replace Supabase UUID |
| `reg` | 10-character string; present on all 52 | Existing `student_code` | Direct mapping after uniqueness validation |
| `surname` | text; present on all 52 | Existing `surname` | Direct |
| `first` | text; present on all 52 | Existing `first_name` | Direct |
| `other` | text; populated on 3 profiles | Existing `other_names` | Direct; blank remains null |
| `phone` | text; populated on 36 profiles | Existing `phone` | Direct; missing values remain null |
| `gphone` | text; populated on 29 profiles | Existing `guardian_phone` | Direct; missing values remain null |
| `gender` | text; present on all 52 | New `gender` column | Preserve as source text; validate allowed values before import |
| `dept` | text; present on all 52 | New `department` column | Preserve exact source value |
| `exam` | text; present on all 52 | New `exam_type` column | Preserve exact source value |
| `fee` | integer; present on all 52 | New `fee_amount` numeric column | Preserve amount; confirm currency and meaning before using in fee calculations |
| `added` | ISO date string; present on all 52 | New `app_created_on` date column | Preserve source date separately from database `created_at` |
| `start` | YYYY-MM string; present on all 52 | New `enrollment_month` text column | Preserve as month; do not mistake it for academic session |
| `photo` | base64-like text; populated on 39 profiles | Private Supabase Storage object; store only a private path on student row | Never store base64 in a public profile response or commit it to GitHub |

## Fields requiring clarification or separate handling

- `academic_session` is required by the existing staging table. User has explicitly confirmed `2026/2027` as the academic session for all 52 profiles. Map this value to `academic_session`; retain the backup's `start` month separately as `enrollment_month`.
- `cycle`, `dbase`, `dstart`, `expiry`, and `next` occur only on a small subset of records. Their business meaning must be confirmed before migration.
- Payment records contain additional billing and receipt fields. They must be reconciled against the student stable ID before a separate payment migration.
- Attendance records are keyed by registration value and date. They need a separate foreign-key mapping and duplicate-date review.
- The backup has no expenditure records.

## Import safety decisions

1. Upsert by `app_student_id`, not by a generated UUID or surname.
2. Enforce unique `student_code` and unique normalized username before creating any Auth users.
3. Keep photos in a private bucket and authorize access through the student's linked identity.
4. Do not import payment or attendance data as a side effect of student-profile import.
5. Do not print student values, photos, or generated passwords in browser reports, GitHub commits, or function logs.
6. Keep the real import disabled until the schema migration, server-side importer, dummy-account login, voluntary password-update flow, and cross-student isolation tests are complete.

## Current status

This is a mapping specification only. No database schema, student record, photo, payment, attendance record, or Auth account was changed.
