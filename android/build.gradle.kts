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
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    val configureAndroid: (Project) -> Unit = { p ->
        val android = p.extensions.findByName("android")
        if (android != null) {
            try {
                val method = android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                method.invoke(android, 36)
            } catch (_: Exception) {
                try {
                    val method = android.javaClass.getMethod("setCompileSdk", Int::class.javaObjectType)
                    method.invoke(android, 36)
                } catch (_: Exception) {}
            }
        }
    }
    if (project.state.executed) {
        configureAndroid(project)
    } else {
        project.afterEvaluate {
            configureAndroid(project)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
