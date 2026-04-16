# Flutter ProGuard Rules

# Keep the PathUtils class which is often used by plugins but might be stripped by R8 
# especially in newer Flutter versions where internal structures have changed.
-keep class io.flutter.util.PathUtils { *; }

# Also keep common Flutter internal classes to prevent similar issues
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# Suppress warnings for missing Google Play Core classes (common in Flutter)
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.gms.**

# Suppress warnings for other common optional components
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**
