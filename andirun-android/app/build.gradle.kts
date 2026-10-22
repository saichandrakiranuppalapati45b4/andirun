plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.andirun.worker"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.andirun.worker"
        minSdk = 28
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        ndk {
            abiFilters.addAll(listOf("arm64-v8a"))
        }

        externalNativeBuild {
            cmake {
                cppFlags.addAll(listOf("-std=c++17", "-O3"))
                arguments.addAll(listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DGGML_VULKAN=ON",
                    "-DGGML_NATIVE=OFF",
                    "-DGGML_CPU_ARM_ARCH=armv8.7-a"
                ))
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}
