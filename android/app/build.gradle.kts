plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.qshh.flutter_mc"
    // 不用 flutter.compileSdkVersion（=36）：permission_handler_android 14.x 的
    // AAR 元数据要求依赖方至少用 37 编译，否则 :app:checkReleaseAarMetadata 直接
    // 报 "requires libraries and applications that depend on it to compile against
    // version 37 or later"。compileSdk 只影响"能用哪些新 API"，与 targetSdk（运行
    // 期行为）和 minSdk（可安装范围）互不相干，向后兼容，所以单独抬高它没副作用。
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.qshh.flutter_mc"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ── 宿主承载层 native（change android-embedded-jvm-host）──────────────
        // 首期只带 arm64-v8a 的 JRE 与 native（design D2）：非 arm64 设备上本地服务器入口
        // 置灰并给出补齐途径（spec「JRE 产物按客户端锚点主版本提供」）。
        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=c++_shared")
            }
        }
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    // native 源在 src/main/cpp（CMakeLists.txt），见同目录 third_party/NOTICE.md 的许可登记。
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // JRE 产物以 `.tar.xz` 携带（universal + bin-<arch>，照参考实现 RuntimeUtils.installJava 口径），
    // 解包在 Android 侧完成：commons-compress 解 tar，tukaani xz 解 xz。
    // 两者均为 Apache-2.0 / Public Domain 类宽松许可，来源与许可见 android/app/src/main/cpp/third_party/NOTICE.md。
    implementation("org.apache.commons:commons-compress:1.27.1")
    implementation("org.tukaani:xz:1.10")
}

flutter {
    source = "../.."
}
