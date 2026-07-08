# Backend and Content Infrastructure

The two folders here form one data delivery workflow:

1. `content-pipeline/` researches, constructs, reviews, validates, and exports vocabulary data.
2. `supabase/` defines the database schema and provides migrations and maintenance SQL.
3. Approved pipeline exports are loaded into Supabase using the instructions in
   `content-pipeline/constructed_data/band_4_0_v1/supabase_import/README.md`.
4. The Phase 1 target database can be verified with
   `supabase/manual/run_phase1_target_verification.ps1`.
5. The same backend can be verified locally in a disposable Docker Postgres
   container with `supabase/manual/run_phase1_local_docker_verification.ps1`.

Generated pipeline output and downloaded source repositories are intentionally excluded from Git. Database migrations and reviewed curriculum exports are versioned.
