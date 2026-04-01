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

// Satukan output plugin ke traka/build hanya jika plugin & proyek satu drive (Windows).
// Jika repo di D: dan pub cache di C:, memaksa buildDir ke D: memicu Kotlin/Gradle
// "this and base files have different roots" untuk sumber di C:.
subprojects {
    val rootPath = rootProject.projectDir.absolutePath
    val subPath = project.projectDir.absolutePath
    val os = System.getProperty("os.name")?.lowercase() ?: ""
    val sameDrive =
        if (os.contains("windows")) {
            rootPath.length >= 2 &&
                subPath.length >= 2 &&
                rootPath[0].equals(subPath[0], ignoreCase = true) &&
                rootPath[1] == ':' &&
                subPath[1] == ':'
        } else {
            true
        }
    if (sameDrive) {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
