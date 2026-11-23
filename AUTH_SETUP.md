# Stage 4 — Authentication Integration Scaffold

This branch wires the login form to Supabase Auth, but intentionally does not contain project credentials or claim database access.

## Setup
1. Copy `supabase-config.example.js` to `supabase-config.js`.
2. Fill in the Supabase Project URL and **publishable/anon key only**.
3. Never use a `service_role` key in browser code.
4. Load `supabase-config.js` before `student-login.html` script runs.
5. Configure Supabase Auth redirect URLs for the deployed host.
6. Test with a dedicated test account and verify that no private student data is exposed.

The configuration file is excluded by recommendation from committing secrets (the publishable key is designed for public clients but should still be paired with strict RLS).

## Current limitation
Authentication only. This scaffold does not query student tables, create accounts, change passwords, or guarantee row-level security. Those are later steps and require policy review/testing.
