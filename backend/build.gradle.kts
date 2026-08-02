plugins {
    java
    id("org.springframework.boot") version "4.1.0"
    id("io.spring.dependency-management") version "1.1.7"
    id("org.openapi.generator") version "7.23.0"
}

group = "com.woorisai"
version = "0.1.0-SNAPSHOT"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(25)
    }
}

repositories {
    mavenCentral()
}

extra["springModulithVersion"] = "2.1.0"

dependencies {
    implementation("com.google.firebase:firebase-admin:9.10.0")
    implementation("software.amazon.awssdk:s3:2.48.3") {
        exclude(group = "software.amazon.awssdk", module = "apache5-client")
        exclude(group = "software.amazon.awssdk", module = "netty-nio-client")
    }
    implementation("software.amazon.awssdk:url-connection-client:2.48.3")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.springframework.boot:spring-boot-starter-flyway")
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("org.springframework.boot:spring-boot-starter-webmvc")
    implementation("org.springframework.modulith:spring-modulith-starter-jpa") {
        exclude(group = "org.springframework.modulith", module = "spring-modulith-moments")
    }

    compileOnly("org.projectlombok:lombok")
    annotationProcessor("org.projectlombok:lombok")

    runtimeOnly("org.flywaydb:flyway-database-postgresql")
    runtimeOnly("org.postgresql:postgresql")

    developmentOnly("com.h2database:h2")
    testImplementation("com.networknt:json-schema-validator:1.5.6")
    testImplementation("org.springframework.boot:spring-boot-starter-data-jpa-test")
    testImplementation("org.springframework.boot:spring-boot-starter-webmvc-test")
    testImplementation("org.springframework.boot:spring-boot-testcontainers")
    testImplementation("org.springframework.modulith:spring-modulith-starter-test")
    testImplementation("org.testcontainers:testcontainers-postgresql")
    testRuntimeOnly("com.h2database:h2")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

dependencyManagement {
    imports {
        mavenBom(
            "org.springframework.modulith:spring-modulith-bom:" +
                property("springModulithVersion"),
        )
    }
}

dependencyLocking {
    lockAllConfigurations()
}

tasks.withType<JavaCompile>().configureEach {
    options.encoding = "UTF-8"
}

val openApiSpec = layout.projectDirectory.file("../contracts/openapi-v2.yaml")

// ErrorCatalogTest reads the published contract instead of restating it, so the spec is an input
// of every test task: editing it alone must be able to fail the build.
tasks.withType<Test>().configureEach {
    systemProperty("woorisai.contract.openapi", openApiSpec.asFile.absolutePath)
    inputs.file(openApiSpec).withPropertyName("openApiSpec").withPathSensitivity(PathSensitivity.RELATIVE)
}

tasks.named<Test>("test") {
    useJUnitPlatform {
        excludeTags("postgres")
    }
}

val postgresTest = tasks.register<Test>("postgresTest") {
    description = "Runs PostgreSQL clean-schema, dialect, and concurrency tests."
    group = "verification"
    testClassesDirs = sourceSets["test"].output.classesDirs
    classpath = sourceSets["test"].runtimeClasspath
    useJUnitPlatform {
        includeTags("postgres")
    }
    shouldRunAfter(tasks.named("test"))
}

tasks.named("check") {
    dependsOn("openApiValidate", postgresTest)
}

openApiValidate {
    inputSpec.set(layout.projectDirectory.file("../contracts/openapi-v2.yaml"))
    recommend.set(true)
    treatWarningsAsErrors.set(true)
}

tasks.withType<AbstractArchiveTask>().configureEach {
    isPreserveFileTimestamps = false
    isReproducibleFileOrder = true
}
