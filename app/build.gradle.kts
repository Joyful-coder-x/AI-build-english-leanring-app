import java.util.Properties

plugins {
    // AGP 9.0+ has built-in Kotlin (no kotlin.android plugin needed), but the
    // Compose Compiler plugin must still be applied when Compose is enabled.
    // Its version must match AGP 9.2's built-in Kotlin (2.2.x).
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    // kotlinx-serialization: required by the Supabase SDK to (de)serialize models.
    alias(libs.plugins.kotlin.serialization)
}

// Supabase config is read from local.properties (gitignored) and surfaced via
// BuildConfig, so the keys are never hard-coded in committed source.
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val supabaseUrl: String = localProperties.getProperty("SUPABASE_URL").orEmpty()
val supabaseAnonKey: String = localProperties.getProperty("SUPABASE_ANON_KEY").orEmpty()

android {
    namespace = "com.example.firsttest"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "com.example.firsttest"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField("String", "SUPABASE_URL", "\"$supabaseUrl\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"$supabaseAnonKey\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)

    // Supabase (Phase 4 backend). Fake repositories remain the default; this
    // wires the client so Supabase*Repository impls can be added incrementally.
    implementation(platform(libs.supabase.bom))
    implementation(libs.supabase.postgrest)
    implementation(libs.supabase.auth)
    implementation(libs.supabase.storage)
    implementation(libs.ktor.client.android)

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test.junit4)
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)
}
