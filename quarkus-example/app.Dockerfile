FROM maven:3.6.2-jdk-8-slim@sha256:2b54b5981f55838fc4fba956e0092bc97b932ef011c7f70ca85caec337711741 as maven

FROM adoptopenjdk/openjdk11:jdk-11.0.4_11-slim@sha256:79f43f49f505df27528a3dce52e30339116ed6716b1f658206ba76caca26c85b \
  as dev

COPY --from=maven /usr/share/maven /usr/share/maven
RUN ln -s /usr/share/maven/bin/mvn /usr/bin/mvn
ENV MAVEN_HOME=/usr/share/maven
ENV MAVEN_CONFIG=/root/.m2

WORKDIR /workspace
RUN mvn io.quarkus:quarkus-maven-plugin:0.22.0:create \
    -DprojectGroupId=org.acme \
    -DprojectArtifactId=getting-started \
    -DclassName="org.acme.quickstart.GreetingResource" \
    -Dpath="/hello" && \
    rm -r src/test/java/org/acme && echo 'package org; public class T { @org.junit.jupiter.api.Test public void t() { } }' > src/test/java/org/T.java
COPY app/pom.xml .
RUN mvn package && \
  rm -r src target mvnw*
COPY app .

ENTRYPOINT [ "mvn", "compile", "quarkus:dev" ]
CMD [ "-Dquarkus.http.host=0.0.0.0", "-Dquarkus.http.port=8080" ]
