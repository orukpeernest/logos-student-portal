# LOGOS student login and Android backup import — implementation contract

## Confirmed student sign-in rule
- The source of the serial suffix is the student's `reg` field from the LOGOS Student Management app backup.
- Extract the final four numeric characters from the complete registration value, ignoring punctuation and letters.
- Username: uppercase surname (spaces removed) immediately followed by those four digits.
- Initial password: the same four digits.
- Students must be required to replace the initial password on first successful sign-in.

Example only: for a registration value `LGS/26/001`, the numeric sequence is `26001` and the final four digits are `6001`. The username uses the student's surname plus `6001`.

## Backup contract currently observed
The exported JSON has a top-level `students` array. Student records include app identifier `id`, registration value `reg`, surname `surname`, and other profile fields. The full backup may contain sensitive student information and embedded photos; do not print records or credentials into browser logs, previews, or error messages.

## Current branch implementation
- `student-import.js` validates the JSON structure, required fields, four-digit suffix availability, and collisions in generated usernames.
- The admin page can select a backup and display an aggregate validation report with row numbers and issue descriptions.
- Validation is local in the browser. It does not transmit, insert, update, or delete student records.
- Automated checks cover valid records, duplicate usernames, malformed records, and unsupported file shapes.

## Required backend work before enabling real import or student login
1. Inspect the actual Supabase schema, student/payment/attendance relationships, RLS policies, and existing RPC definitions. Do not assume an RPC or table exists.
2. Implement a privileged, transactional import RPC that accepts validated backup data, upserts by the stable Android app student ID, preserves existing links, and reports created/updated/skipped counts without returning sensitive records.
3. Keep the import admin-only. Never put a service-role key or privileged secret in browser code.
4. Implement a secure username-to-auth-account mapping so students enter the agreed username and password, even if the underlying auth provider requires a different internal identifier.
5. Store only a password hash / provider-managed credential. Do not store plaintext initial passwords or send a list of generated passwords to the browser.
6. Mark accounts as requiring password change and enforce it server-side before allowing access to student records.
7. Rate-limit login attempts and protect against username enumeration. Four-digit initial passwords are temporary bootstrap credentials only.
8. Verify every student data query is scoped to the authenticated student's linked app record. Test cross-student access denial for profile, fees, payments, receipts, attendance, and announcements.
9. Test backup import against a copy/staging environment before production data is changed.

## Explicitly not complete
No live student import, credential creation, student authentication, first-login password change, or Supabase policy change is implemented or verified by this branch. The production website and main branch remain unchanged.
