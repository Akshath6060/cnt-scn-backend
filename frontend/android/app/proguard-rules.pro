# TensorFlow Lite ----------------------------------------------------------
# The interpreter reaches its native bindings reflectively; shrinking them
# produces a runtime UnsatisfiedLinkError rather than a build error.
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }
-dontwarn org.tensorflow.lite.**

# WorkManager --------------------------------------------------------------
# The background cleanup worker is instantiated by name by the OS.
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.ListenableWorker { <init>(...); }
-keep class dev.fluttercommunity.workmanager.** { *; }

# Flutter embedding --------------------------------------------------------
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }

# flutter_contacts ---------------------------------------------------------
-keep class co.quis.flutter_contacts.** { *; }
