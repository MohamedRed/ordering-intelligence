plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.orderingintelligence.consumer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    flavorDimensions += "dist"

    productFlavors {
        create("google") {
            dimension = "dist"
            applicationId = "com.orderingintelligence.consumer"
        }
        create("firetv") {
            dimension = "dist"
            // Keep the same app id so tokens/deep links work across stores; Amazon allows reuse.
            applicationId = "com.orderingintelligence.consumer"
            // Hint to Amazon review that this build targets Fire TV.
            manifestPlaceholders["amazonDevice"] = "firetv"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.orderingintelligence.consumer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        val facebookAppId = project.findProperty("FACEBOOK_APP_ID")?.toString().orEmpty()
        val facebookClientToken = project.findProperty("FACEBOOK_CLIENT_TOKEN")?.toString().orEmpty()
        val facebookDisplayName =
            project.findProperty("FACEBOOK_DISPLAY_NAME")?.toString().orEmpty().ifEmpty {
                "Ordering Intelligence"
            }
        resValue("string", "facebook_app_id", facebookAppId)
        resValue("string", "facebook_client_token", facebookClientToken)
        resValue("string", "facebook_display_name", facebookDisplayName)
        resValue(
            "string",
            "facebook_login_protocol_scheme",
            if (facebookAppId.isNotEmpty()) "fb$facebookAppId" else "fb$applicationId"
        )

        manifestPlaceholders["appAuthRedirectScheme"] =
            project.findProperty("APP_AUTH_REDIRECT_SCHEME")?.toString().orEmpty().ifEmpty {
                applicationId
            }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.car.app:app:1.4.0")
    implementation("com.google.android.gms:play-services-wearable:18.1.0")
}
