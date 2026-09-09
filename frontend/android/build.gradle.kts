allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Align JVM targets across every plugin module.
//
// Several plugins (tflite_flutter among them) declare Kotlin jvmTarget 17 but
// leave Java on the AGP default of 11. Gradle 9 treats that mismatch as a hard
// error rather than a warning, so both are pinned to 17 for every subproject
// here instead of patching each plugin.
//
// Two details matter:
//  * this block is registered BEFORE the evaluationDependsOn block below,
//    because that block forces :app to evaluate and afterEvaluate hooks cannot
//    be added to an already-evaluated project;
//  * `options.release` is cleared as well as source/target compatibility.
//    AGP sets `--release 11`, which takes precedence over sourceCompatibility,
//    so setting compatibility alone leaves javac on 11.
subprojects {
    afterEvaluate {
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
            options.release.set(null as Int?)
        }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
        .configureEach {
            compilerOptions.jvmTarget.set(
                // tflite_flutter 0.12.1 explicitly compiles Java for 11.
                // Keep its Kotlin task on the same target; forcing it to 17
                // makes Gradle 9 reject the plugin before compilation starts.
                when (project.name) {
                    "tflite_flutter" ->
                        org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
                    "workmanager_android" ->
                        org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
                    else -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                }
            )
        }
}
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
