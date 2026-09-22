FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

USER root

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       qemu-system-x86 \
       qemu-utils \
       novnc \
       websockify \
       gh \
       jq \
       unzip \
       ca-certificates \
       procps \
    && rm -rf /var/lib/apt/lists/*

USER vscode
