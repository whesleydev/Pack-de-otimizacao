plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.otm.pack"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.otm.pack"
        minSdk = 26
        targetSdk = 34
        versionCode = 46
        versionName = "2.25.0"
    }

    signingConfigs {
        create("release") {
            storeFile = rootProject.file("keystore/otm-release.jks")
            storePassword = "00deUdia"
            keyAlias = "otm"
            keyPassword = "00deUdia"
        }
    }

    buildTypes {
        release {
            // Keystore fixa e versionada: a mesma assinatura em toda atualização,
            // então dá para instalar por cima (sem desinstalar) sem erro.
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    buildFeatures { buildConfig = true }

    // MP3 guardados sem compressão: assets.openFd() só funciona em arquivos
    // STORED; se forem comprimidos, o som não toca no APK release.
    androidResources {
        noCompress += "mp3"
    }

    packaging {
        resources.excludes += setOf("META-INF/*.kotlin_module")
    }
}

// Os scripts do pack são a fonte da verdade em <repo>/scripts. O app embarca
// uma cópia em assets/pack/scripts (é o que PackAssets.ensureShellCopy leva para
// /data/local/tmp/otm-pack no aparelho). Sem este sync o asset ficava preso numa
// versão antiga e o app rodava script velho. Sync (não Copy) para remover sobras.
val packScriptsDir = rootProject.file("scripts")
val syncPackAssets by tasks.registering(Sync::class) {
    onlyIf { packScriptsDir.isDirectory }
    from(packScriptsDir) { exclude("**/.git/**", "**/*.log") }
    into(layout.projectDirectory.dir("src/main/assets/pack/scripts"))
}
val syncPackVersion by tasks.registering(Copy::class) {
    val v = rootProject.file("VERSION")
    onlyIf { v.isFile }
    from(v)
    into(layout.projectDirectory.dir("src/main/assets/pack"))
}
tasks.named("preBuild") { dependsOn(syncPackAssets, syncPackVersion) }

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.activity:activity-ktx:1.9.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // Shizuku (Apache-2.0)
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")

    // ADB por Wi-Fi (libadb-android, Apache-2.0)
    implementation("com.github.MuntashirAkon:libadb-android:3.1.1")
    implementation("com.github.MuntashirAkon:sun-security-android:1.1")
    implementation("org.bouncycastle:bcpkix-jdk15to18:1.81")
}
