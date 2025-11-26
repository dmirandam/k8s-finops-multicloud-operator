

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    bash \
    ca-certificates \
    gnupg \
    git \
    jq \
    unzip \
    tar \
    gzip \
    sed \
    grep \
    less \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && mv kubectl /usr/local/bin/

RUN curl --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" --output eksctl.tar.gz && \
    tar -xzf eksctl.tar.gz && \
    mv eksctl /usr/local/bin/ && \
    rm eksctl.tar.gz

RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash



RUN apt-get clean && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-c"]

CMD ["bash"]