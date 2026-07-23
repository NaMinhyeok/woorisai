FROM eclipse-temurin:25-jdk-jammy@sha256:0348e7b24ad4479cf35927b750671bb4b78465c303003b08536f6f2fa6f180cd AS build

WORKDIR /workspace

COPY backend ./backend
COPY contracts ./contracts

RUN cd backend \
    && ./gradlew --no-daemon openApiValidate bootJar \
    && jar_count="$(find build/libs -maxdepth 1 -type f -name '*.jar' | wc -l)" \
    && test "$jar_count" -eq 1 \
    && cp build/libs/*.jar /workspace/woorisai.jar

FROM eclipse-temurin:25-jre-jammy@sha256:b8ba5fca9d88b6ecc3a46c8e75b744f84aca9a9d08587901b5ab480baf641ab5 AS runtime

LABEL org.opencontainers.image.source="https://github.com/NaMinhyeok/woorisai"

WORKDIR /app

COPY --from=build --chown=10001:10001 /workspace/woorisai.jar /app/woorisai.jar

USER 10001:10001

EXPOSE 8080

CMD ["java", "-jar", "/app/woorisai.jar"]
