#!/bin/bash

############################################################################
# Alpenglow Two-Stage Docker Build Script
# 
# Stage 1: Build base image with all dependencies
# Stage 2: Build verification runner using the base
############################################################################

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "🐳 Alpenglow Two-Stage Docker Build"
echo "===================================="
echo

# Stage 1: Build base image with dependencies
print_step "Building base image with all dependencies..."
if docker build -t alpenglow-verification-base .; then
    print_success "Base image built successfully"
else
    print_error "Failed to build base image"
    exit 1
fi

echo

# Stage 2: Build verification runner
print_step "Building verification runner using base image..."
if docker build -f Dockerfile.quick -t alpenglow-verification .; then
    print_success "Verification runner built successfully"
else
    print_error "Failed to build verification runner"
    exit 1
fi

echo

# Show final images
print_step "Docker images created:"
docker images | grep alpenglow-verification

echo

print_success "Build complete! Usage:"
echo "• Test base image:        docker run --rm alpenglow-verification-base"
echo "• Run full verification:  docker run --rm alpenglow-verification"
echo

print_step "Quick verification test:"
docker run --rm alpenglow-verification
