allprojects {
    repositories {
        // 国内网络访问 dl.google.com 常被重置（实测 Recv failure: Connection was reset），
        // 导致 androidx 依赖下载失败、`flutter build apk` 直接崩在 mergeReleaseNativeLibs。
        // 阿里云镜像是 google() 的同源镜像，放在前面先命中；取不到时仍会回落到官方源。
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
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
// 本机 SDK 中 28.2.13676358 的 NDK 目录是空壳（下载损坏），
// 而部分插件（如 jni）在自身脚本里把 ndkVersion 设回 flutter.ndkVersion。
// 这里统一在所有子工程完成配置后再压回已完整安装的 25.1（本项目无自研 C/C++）。
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            androidExt.ndkVersion = "25.1.8937393"
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
