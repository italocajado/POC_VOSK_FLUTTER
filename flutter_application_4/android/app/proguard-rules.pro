# Keep VOSK and JNA classes
-keep class org.vosk.** { *; }
-keep class com.sun.jna.** { *; }
-keep class libvosk.** { *; }

# Keep JNA from being optimized
-keepclasseswithmembernames class * {
    native <methods>;
}

# JNA specific
-dontwarn java.awt.**
-dontwarn org.slf4j.**
-dontwarn com.sun.jna.**

# Keep JNA callbacks
-keepclassmembers class * extends com.sun.jna.* {
    <fields>;
    <methods>;
}

# Keep JNA structures
-keepclassmembers class * extends com.sun.jna.Structure {
    <fields>;
}