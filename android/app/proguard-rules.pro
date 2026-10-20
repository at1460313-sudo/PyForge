# Chaquopy uses reflection into python.org classes; do not strip.
-keep class com.chaquo.python.** { *; }
-keep class org.python.** { *; }
-keep class com.pyforge.ide.** { *; }
-dontwarn org.python.**
