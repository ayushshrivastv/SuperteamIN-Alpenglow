# Alpenglow Verification Base Image - Dependencies Only
FROM ubuntu:22.04

LABEL maintainer="Ayush Srivastava"
LABEL description="Base environment with all dependencies for Alpenglow formal verification"
LABEL version="2.0"

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    openjdk-11-jdk \
    python3 \
    python3-pip \
    build-essential \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Set Java environment
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV PATH=$PATH:$JAVA_HOME/bin

# Create verification user first
RUN useradd -m -s /bin/bash verifier

# Install Rust for verifier user
USER verifier
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/home/verifier/.cargo/bin:${PATH}"

# Switch back to root for remaining installations
USER root

# Install TLA+ Tools with better error handling
WORKDIR /opt
RUN wget -q --timeout=60 --tries=3 https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar || \
    curl -L --connect-timeout 60 --max-time 300 -o tla2tools.jar https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar
ENV CLASSPATH="/opt/tla2tools.jar"

# Install TLAPS (TLA+ Proof System) - optional
RUN apt-get update && apt-get install -y \
    ocaml \
    opam \
    zenon \
    || echo "TLAPS installation skipped - optional component"

# Create workspace directory
RUN mkdir -p /home/verifier/workspace && chown -R verifier:verifier /home/verifier
USER verifier
WORKDIR /home/verifier/workspace

# Create environment check script
RUN echo '#!/bin/bash\n\
echo "Alpenglow Dependencies Base Image"\n\
echo "================================="\n\
echo "Java: $(java -version 2>&1 | head -1)"\n\
echo "Rust: $(rustc --version)"\n\
echo "Cargo: $(cargo --version)"\n\
echo "TLA+ Tools: $(test -f /opt/tla2tools.jar && echo \"Available\" || echo \"Not available\")"\n\
echo ""\n\
echo "Ready for Alpenglow verification!"\n\
echo "Mount your project and run verification scripts."\n\
' > check_deps.sh && chmod +x check_deps.sh

# Default command shows environment status
CMD ["./check_deps.sh"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD java -version > /dev/null 2>&1 && rustc --version > /dev/null 2>&1
