# Regras ProGuard do app (release sem minify por padrão).
-keep class rikka.shizuku.** { *; }
-keep class io.github.muntashirakon.adb.** { *; }
-dontwarn org.bouncycastle.**
-dontwarn android.sun.**
