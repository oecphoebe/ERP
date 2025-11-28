#FROM openjdk:21-slim AS builder -- deprecated as of 2025/11/10
FROM eclipse-temurin:21-jdk-noble AS builder

WORKDIR /app

COPY mvnw .
RUN chmod -R 755 ./mvnw
COPY .mvn .mvn
COPY pom.xml .
COPY src src
RUN ./mvnw install -DskipTests

FROM eclipse-temurin:21-alpine

WORKDIR /app

COPY --from=builder /app/target/cpar-api.jar app.jar
ARG VERSION_TAG
ENV VERSION_TAG_ENV=${VERSION_TAG}
CMD ["java", "-Dserver.version=$VERSION_TAG_ENV", "-jar", "app.jar"]
