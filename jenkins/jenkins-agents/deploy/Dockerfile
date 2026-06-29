# Jenkins inbound deploy agent
FROM jenkins/inbound-agent:jdk21

USER root

SHELL ["/bin/bash", "-e", "-u", "-o", "pipefail", "-c"]

ARG KUBECTL_VERSION
ARG HELM_VERSION
ARG TARGETARCH=amd64

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        gzip \
        openssh-client \
        tar \
    && rm -rf /var/lib/apt/lists/*

# kubectl
RUN test -n "${KUBECTL_VERSION}" && \
    curl -fsSL \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
        -o /usr/local/bin/kubectl && \
    chmod 0755 /usr/local/bin/kubectl

# Helm
RUN test -n "${HELM_VERSION}" && \
    curl -fsSL \
        "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" \
        -o /tmp/helm.tar.gz && \
    tar -xzf /tmp/helm.tar.gz -C /tmp && \
    install -m 0755 \
        "/tmp/linux-${TARGETARCH}/helm" \
        /usr/local/bin/helm && \
    rm -rf \
        /tmp/helm.tar.gz \
        "/tmp/linux-${TARGETARCH}"

RUN java -version && \
    ssh -V && \
    git --version && \
    kubectl version --client=true && \
    helm version --short

USER jenkins

WORKDIR /home/jenkins/agent
