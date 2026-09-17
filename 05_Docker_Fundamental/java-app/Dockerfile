# Multi-stage: the JDK is only needed to compile, the JRE is enough to run.
# This keeps the shipped image far smaller than one containing the full JDK.
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /src
COPY Main.java .
RUN javac -d /out Main.java

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /out .
ENV PORT=8080
EXPOSE 8080
CMD ["java", "Main"]
