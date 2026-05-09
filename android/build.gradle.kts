allprojects {
    repositories {
        google()
        mavenCentral()
        // FFmpeg Kit binaries were removed from Maven Central after the project retired.
        // This mirror still serves the AAR required by ffmpeg_kit_flutter_min_gpl.
        maven { url = uri("https://artifactory.appodeal.com/appodeal-public") }
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
