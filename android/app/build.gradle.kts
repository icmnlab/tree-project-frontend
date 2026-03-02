import java.util.Properties
import java.io.FileInputStream
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.sustainable.treeai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    androidResources {
        noCompress += "tflite"
    }
    
    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sustainable.treeai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 從 gradle.properties 讀取 Google Maps API Key（安全方式，不會提交到 Git）
        val googleMapsApiKey = project.findProperty("GOOGLE_MAPS_API_KEY") as String? ?: ""
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = googleMapsApiKey
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { rootProject.file("app/$it") }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // Signing with the release keys
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), file("proguard-rules.pro"))
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 強制覆蓋 tflite_flutter 內建的 TFLite 2.11.0 → 2.16.1
    // 解決模型 op 版本不相容導致 allocateTensors 失敗的問題
    // (模型使用 CONV_2D v5, RANGE v3 等，2.11.0 可能不完整支援)
    implementation("org.tensorflow:tensorflow-lite:2.16.1")
    // GPU delegate (匹配版本；即使未啟用也需與主 runtime 一致避免衝突)
    implementation("org.tensorflow:tensorflow-lite-gpu:2.16.1")
}
