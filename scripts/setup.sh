#!/bin/bash

#############################################################################
# Alpenglow Formal Verification Environment Setup Script
# 
# This script installs and configures all necessary tools for running
# TLA+ specifications, model checking with TLC, and theorem proving with TLAPS.
#############################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TLA_VERSION="1.8.0"
TLAPS_VERSION="1.4.5"
JAVA_MIN_VERSION="11"

# Helper functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Check operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        print_error "Unsupported operating system: $OSTYPE"
        exit 1
    fi
    print_info "Detected OS: $OS"
}

# Check Java installation
check_java() {
    print_info "Checking Java installation..."
    
    if check_command java; then
        JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f1)
        if [ -z "$JAVA_VERSION" ]; then
            JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f2)
        fi
        
        if [ "$JAVA_VERSION" -ge "$JAVA_MIN_VERSION" ]; then
            print_info "Java $JAVA_VERSION found (required: >= $JAVA_MIN_VERSION)"
        else
            print_error "Java version $JAVA_VERSION is too old (required: >= $JAVA_MIN_VERSION)"
            install_java
        fi
    else
        print_warn "Java not found. Installing..."
        install_java
    fi
}

# Install Java
install_java() {
    print_info "Installing Java..."
    
    if [ "$OS" == "macos" ]; then
        if check_command brew; then
            brew install openjdk@11
            echo 'export PATH="/usr/local/opt/openjdk@11/bin:$PATH"' >> ~/.zshrc
        else
            print_error "Homebrew not found. Please install Java manually."
            exit 1
        fi
    elif [ "$OS" == "linux" ]; then
        if check_command apt-get; then
            sudo apt-get update
            sudo apt-get install -y openjdk-11-jdk
        elif check_command yum; then
            sudo yum install -y java-11-openjdk
        else
            print_error "Package manager not found. Please install Java manually."
            exit 1
        fi
    fi
}

# Install TLA+ toolbox
install_tla() {
    print_info "Installing TLA+ tools..."
    
    # Create tools directory
    mkdir -p ~/tla-tools
    cd ~/tla-tools
    
    # Download TLA+ tools
    print_info "Downloading TLA+ tools version $TLA_VERSION..."
    curl -L -o tla2tools.jar \
        "https://github.com/tlaplus/tlaplus/releases/download/v${TLA_VERSION}/tla2tools.jar"
    
    # Create wrapper scripts
    print_info "Creating wrapper scripts..."
    
    # TLC wrapper
    cat > tlc << 'EOF'
#!/bin/bash
java -cp ~/tla-tools/tla2tools.jar tlc2.TLC "$@"
EOF
    chmod +x tlc
    
    # SANY wrapper
    cat > sany << 'EOF'
#!/bin/bash
java -cp ~/tla-tools/tla2tools.jar tla2sany.SANY "$@"
EOF
    chmod +x sany
    
    # PlusCal wrapper
    cat > pcal << 'EOF'
#!/bin/bash
java -cp ~/tla-tools/tla2tools.jar pcal.trans "$@"
EOF
    chmod +x pcal
    
    # Add to PATH
    if [ "$OS" == "macos" ]; then
        echo 'export PATH="$HOME/tla-tools:$PATH"' >> ~/.zshrc
        echo 'export PATH="$HOME/tla-tools:$PATH"' >> ~/.bash_profile
    else
        echo 'export PATH="$HOME/tla-tools:$PATH"' >> ~/.bashrc
    fi
    
    print_info "TLA+ tools installed successfully"
}

# Install TLAPS
install_tlaps() {
    print_info "Installing TLAPS (TLA+ Proof System)..."
    
    if [ "$OS" == "macos" ]; then
        # Download TLAPS for macOS
        cd /tmp
        curl -L -o tlaps.tar.gz \
            "https://github.com/tlaplus/tlapm/releases/download/v${TLAPS_VERSION}/tlaps-${TLAPS_VERSION}-x86_64-darwin.tar.gz"
        tar -xzf tlaps.tar.gz
        sudo mv tlaps-${TLAPS_VERSION} /usr/local/tlaps
        
        # Add to PATH
        echo 'export PATH="/usr/local/tlaps/bin:$PATH"' >> ~/.zshrc
        echo 'export PATH="/usr/local/tlaps/bin:$PATH"' >> ~/.bash_profile
        
    elif [ "$OS" == "linux" ]; then
        # Download TLAPS for Linux
        cd /tmp
        curl -L -o tlaps.tar.gz \
            "https://github.com/tlaplus/tlapm/releases/download/v${TLAPS_VERSION}/tlaps-${TLAPS_VERSION}-x86_64-linux.tar.gz"
        tar -xzf tlaps.tar.gz
        sudo mv tlaps-${TLAPS_VERSION} /usr/local/tlaps
        
        # Add to PATH
        echo 'export PATH="/usr/local/tlaps/bin:$PATH"' >> ~/.bashrc
    fi
    
    print_info "TLAPS installed successfully"
}

# Install additional dependencies
install_dependencies() {
    print_info "Installing additional dependencies..."
    
    if [ "$OS" == "macos" ]; then
        if check_command brew; then
            brew install graphviz dot2tex
        fi
    elif [ "$OS" == "linux" ]; then
        if check_command apt-get; then
            sudo apt-get install -y graphviz texlive-latex-base
        elif check_command yum; then
            sudo yum install -y graphviz texlive-latex
        fi
    fi
}

# Verify installation
verify_installation() {
    print_info "Verifying installation..."
    
    ERRORS=0
    
    # Check TLC
    if ~/tla-tools/tlc -h &> /dev/null; then
        print_info "✓ TLC is working"
    else
        print_error "✗ TLC is not working"
        ERRORS=$((ERRORS + 1))
    fi
    
    # Check SANY
    if ~/tla-tools/sany -h &> /dev/null; then
        print_info "✓ SANY is working"
    else
        print_error "✗ SANY is not working"
        ERRORS=$((ERRORS + 1))
    fi
    
    # Check TLAPS
    if [ -f "/usr/local/tlaps/bin/tlapm" ]; then
        print_info "✓ TLAPS is installed"
    else
        print_warn "⚠ TLAPS not found (optional for model checking)"
    fi
    
    if [ $ERRORS -eq 0 ]; then
        print_info "All tools installed successfully!"
        return 0
    else
        print_error "Some tools failed to install. Please check the errors above."
        return 1
    fi
}

# Create project structure
setup_project() {
    print_info "Setting up project structure..."
    
    # Create necessary directories if they don't exist
    mkdir -p specs
    mkdir -p models
    mkdir -p proofs
    mkdir -p scripts
    mkdir -p docs
    mkdir -p results
    mkdir -p .github/workflows
    
    print_info "Project structure created"
}

# Main installation flow
main() {
    echo "================================================"
    echo "  Alpenglow Formal Verification Setup"
    echo "================================================"
    echo
    
    detect_os
    check_java
    
    # Check if TLA+ tools already installed
    if [ -f "$HOME/tla-tools/tla2tools.jar" ]; then
        print_warn "TLA+ tools already installed. Skipping..."
    else
        install_tla
    fi
    
    # Check if TLAPS already installed
    if [ -f "/usr/local/tlaps/bin/tlapm" ]; then
        print_warn "TLAPS already installed. Skipping..."
    else
        install_tlaps
    fi
    
    install_dependencies
    setup_project
    verify_installation
    
    echo
    echo "================================================"
    echo "  Setup Complete!"
    echo "================================================"
    echo
    echo "Next steps:"
    echo "1. Reload your shell: source ~/.bashrc (or ~/.zshrc on macOS)"
    echo "2. Run model checking: ./scripts/check_model.sh Small"
    echo "3. Run proofs: ./scripts/verify_proofs.sh"
    echo
    print_info "Happy verifying!"
}

# Run main function
main "$@"
