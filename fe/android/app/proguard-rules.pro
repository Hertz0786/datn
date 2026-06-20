# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Play Core stub classes referenced by Flutter embedding (we don't use dynamic features)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Suppress warnings for missing referenced classes
-dontwarn javax.annotation.**
