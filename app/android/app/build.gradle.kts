plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "es.radarlicitaciones.movil"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications usa java.time en versiones de Android que no lo traen.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "es.radarlicitaciones.movil"
        // Android 8: iconos adaptables y canales de notificación sin código de compatibilidad.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // La vuelta del inicio de sesión (AppAuth): es.radarlicitaciones.movil:/oauth2redirect
        manifestPlaceholders["appAuthRedirectScheme"] = "es.radarlicitaciones.movil"
    }

    buildTypes {
        release {
            // Firmado con la clave de depuración para poder probar la versión de release en local; para publicar
            // se configura una clave propia (ver el README).
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
