# Plugins that are reached only from a background isolate, so R8 cannot see the
# call sites.
-keep class com.pravera.flutter_foreground_task.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class be.tramckrijte.workmanager.** { *; }
-keep class io.flutter.plugin.** { *; }

# Google Sign-In / Play Services surface used by the Calendar client.
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
