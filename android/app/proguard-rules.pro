# Flutter & FFI ProGuard rules for Filo
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# SQLite Native FFI & Drivers
-keep class org.sqlite.** { *; }
-keep class com.filo.vault.filo.** { *; }
-dontwarn org.sqlite.**

# Cryptography & PointyCastle
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Keep native methods and FFI structs
-keepclasseswithmembernames class * {
    native <methods>;
}
