# KuaKua Duck

Android vocabulary-learning prototype backed by Supabase and a reviewed content-construction pipeline.

## Repository map

```text
app/                              Android application and tests
backend/
  content-pipeline/               Vocabulary research, construction, validation, and exports
  supabase/                       Database migrations, manual maintenance SQL, and SQL tests
docs/
  architecture/                   Application architecture, data model, and source policy
  content/                        Content construction and review guidance
  plans/                          Active implementation plans with non-overlapping ownership
  product-prototype-v1/           Product specifications and wireframes
gradle/                           Gradle wrapper and shared version catalog
```

## Common commands

Build and test the Android app:

```powershell
.\gradlew.bat test
.\gradlew.bat assembleDebug
```

Build and validate vocabulary content:

```powershell
python backend/content-pipeline/scripts/00_filter_sources.py
python backend/content-pipeline/scripts/01_select_candidates.py
python backend/content-pipeline/scripts/02_enrich_candidates.py
python backend/content-pipeline/scripts/03_validate_constructed_data.py
python backend/content-pipeline/scripts/06_build_approved_level_content.py
python backend/content-pipeline/scripts/07_validate_approved_content.py
python backend/content-pipeline/scripts/05_export_supabase_imports.py
```

See [backend/README.md](backend/README.md) for the content-to-database workflow and [docs/README.md](docs/README.md) for the documentation index.
