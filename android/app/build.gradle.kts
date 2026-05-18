import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val storeFilePath = keystoreProperties.getProperty("storeFile")
val releaseStoreFile = storeFilePath?.let { rootProject.file(it) }
val releaseSigningReady =
    keystorePropertiesFile.exists() &&
        releaseStoreFile != null &&
        releaseStoreFile.isFile &&
        !keystoreProperties.getProperty("keyAlias").isNullOrBlank() &&
        !keystoreProperties.getProperty("keyPassword").isNullOrBlank() &&
        !keystoreProperties.getProperty("storePassword").isNullOrBlank()

android {
    namespace = "com.vidcompressor.vidcompressor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vidcompressor.vidcompressor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // FFmpeg Kit requires minSdk 24+.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")!!.trim()
                keyPassword = keystoreProperties.getProperty("keyPassword")!!.trim()
                storeFile = releaseStoreFile!!
                storePassword = keystoreProperties.getProperty("storePassword")!!.trim()
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (releaseSigningReady) {
                    signingConfigs.getByName("release")
                } else {
                    // Add android/key.properties and android/app/upload-keystore.jks for Play uploads.
                    signingConfigs.getByName("debug")
                }
        }
    }
}

flutter {
    source = "../.."
}
