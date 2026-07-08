# Environment Files Index

These files define the build and version-control environment.
They MUST stay at the project root — moving them breaks the Android build and Android Studio integration.

## Gradle Build System (project root — do not move)

| File / Folder | Purpose |
|---|---|
| `gradlew` | Unix Gradle wrapper entry point |
| `gradlew.bat` | Windows Gradle wrapper entry point |
| `gradle/` | Gradle wrapper JARs and config |
| `gradle.properties` | JVM heap, Kotlin incremental, AndroidX flags |
| `settings.gradle.kts` | Project structure — declares `app` module |
| `build.gradle.kts` | Project-level dependencies and plugin versions |
| `local.properties` | Local SDK path — gitignored, per-machine |
| `.gradle/` | Gradle cache — generated, gitignored |

## Android Studio (project root — do not move)

| File / Folder | Purpose |
|---|---|
| `.idea/` | Android Studio project settings |
| `app/build.gradle.kts` | App module build config: compileSdk, plugins, dependencies |
| `app/src/main/AndroidManifest.xml` | App permissions, activities, intent filters |

## Version Control (project root — do not move)

| File / Folder | Purpose |
|---|---|
| `.git/` | Git repository — contains all commit history |
| `.gitignore` | Ignores build artifacts, local.properties, secrets |
| `.github/` | GitHub-specific config (modernize hooks) |

## Claude Code Config (project root — do not move)

| File / Folder | Purpose |
|---|---|
| `CLAUDE.md` | Claude Code instructions for this project |
| `.claude/` | Claude Code session settings |
| `.agents/` | AI assistant config |

## Key Build Commands

```powershell
# Build debug APK
.\gradlew.bat assembleDebug

# Run unit tests
.\gradlew.bat test

# Build + test
.\gradlew.bat assembleDebug test
```

## Required JDK

Android Gradle Plugin 9.2.1 requires JDK 21+.
Android Studio Ladybug or newer ships with JDK 21.
