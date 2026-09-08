import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "tw.hungmi.justalauncher"
    compileSdk = 34

    defaultConfig {
        applicationId = "tw.hungmi.justalauncher"
        minSdk = 21
        targetSdk = 34
        versionCode = 7
        versionName = "0.7"
    }

    signingConfigs {
        create("release") {
            storeFile = rootProject.file(System.getenv("KEYSTORE_FILE") ?: "release.p12")
            storeType = "PKCS12"
            storePassword = System.getenv("KEYSTORE_PASSWORD")
            keyAlias = System.getenv("KEY_ALIAS") ?: "just-a-launcher"
            keyPassword = System.getenv("KEYSTORE_PASSWORD")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint { checkReleaseBuilds = false }
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}
