plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.contact_scanner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local plugins targeting newer java.time APIs on
        // older Android versions.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.example.contact_scanner"
        // 23 is the floor for tflite_flutter and flutter_contacts.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // TFLite models must not be compressed: the interpreter memory-maps the
    // asset, and a deflated entry cannot be mapped.
    androidResources {
        noCompress += listOf("tflite", "lite")
    }

    buildTypes {
        release {
            // TODO: replace with a real signing config before publishing.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
