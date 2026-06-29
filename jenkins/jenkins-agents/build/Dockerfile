# Docker CLI source
FROM docker:28-cli AS docker-cli

# Jenkins inbound build agent
FROM jenkins/inbound-agent:jdk21

USER root

SHELL ["/bin/bash", "-e", "-u", "-o", "pipefail", "-c"]

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI
COPY --from=docker-cli \
    /usr/local/bin/docker \
    /usr/local/bin/docker

# Docker CLI plugins: buildx và compose
COPY --from=docker-cli \
    /usr/local/libexec/docker/cli-plugins \
    /usr/local/libexec/docker/cli-plugins

RUN java -version && \
    git --version && \
    docker --version && \
    docker buildx version && \
    docker compose version

USER jenkins

WORKDIR /home/jenkins/agent
