#!/usr/bin/env bash
set -euo pipefail

# Blink Installer - Cross-platform installation script
# Installs dnsmasq and configures system for wildcard DNS blocking

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}=== Blink Installer ===${NC}"
echo ""

# Detect OS
detect_os() {
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    elif [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            ubuntu|debian|pop|linuxmint|elementary)
                echo "debian"
                ;;
            fedora|rhel|centos|rocky|almalinux)
                echo "fedora"
                ;;
            arch|manjaro|endeavouros)
                echo "arch"
                ;;
            opensuse*|sles)
                echo "suse"
                ;;
            *)
                echo "unknown"
                ;;
        esac
    else
        echo "unknown"
    fi
}

# Check for root on Linux
check_privileges() {
    if [[ "$(uname)" != "Darwin" ]] && [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script requires root privileges on Linux${NC}"
        echo "Run with: sudo ./install.sh"
        exit 1
    fi
}

# Install dnsmasq based on OS
install_dnsmasq() {
    local os="$1"

    echo -e "${YELLOW}Installing dnsmasq...${NC}"

    case "$os" in
        macos)
            if ! command -v brew &> /dev/null; then
                echo -e "${RED}Error: Homebrew is required on macOS${NC}"
                echo "Install it from: https://brew.sh"
                exit 1
            fi
            brew install dnsmasq
            ;;
        debian)
            apt-get update
            apt-get install -y dnsmasq
            ;;
        fedora)
            dnf install -y dnsmasq
            ;;
        arch)
            pacman -S --noconfirm dnsmasq
            ;;
        suse)
            zypper install -y dnsmasq
            ;;
        *)
            echo -e "${RED}Error: Unsupported OS${NC}"
            echo "Please install dnsmasq manually and run this script again"
            exit 1
            ;;
    esac

    echo -e "${GREEN}dnsmasq installed${NC}"
}

# Configure dnsmasq
configure_dnsmasq() {
    local os="$1"

    echo -e "${YELLOW}Configuring dnsmasq...${NC}"

    # Create dnsmasq.d directory if it doesn't exist
    mkdir -p /etc/dnsmasq.d

    # Create main dnsmasq config if needed
    local dnsmasq_conf="/etc/dnsmasq.conf"
    if [[ "$os" == "macos" ]]; then
        dnsmasq_conf="/opt/homebrew/etc/dnsmasq.conf"
        if [[ ! -f "$dnsmasq_conf" ]]; then
            dnsmasq_conf="/usr/local/etc/dnsmasq.conf"
        fi
    fi

    # Ensure conf-dir is included
    if [[ -f "$dnsmasq_conf" ]]; then
        if ! grep -q "conf-dir=/etc/dnsmasq.d" "$dnsmasq_conf" 2>/dev/null; then
            echo "conf-dir=/etc/dnsmasq.d/,*.conf" >> "$dnsmasq_conf"
        fi
    else
        echo "conf-dir=/etc/dnsmasq.d/,*.conf" > "$dnsmasq_conf"
    fi

    # Create empty blocklist file
    touch /etc/dnsmasq.d/blink-blocklist.conf
    echo "# Blink blocklist - managed by blink CLI" > /etc/dnsmasq.d/blink-blocklist.conf

    # Configure dnsmasq to listen on localhost and forward to upstream DNS
    cat > /etc/dnsmasq.d/blink-config.conf << 'EOF'
# Blink dnsmasq configuration
listen-address=127.0.0.1
port=53
bind-interfaces
no-resolv
# Use common public DNS servers as upstream
server=8.8.8.8
server=8.8.4.4
server=1.1.1.1
EOF

    echo -e "${GREEN}dnsmasq configured${NC}"
}

# Configure system DNS to use local dnsmasq
configure_system_dns() {
    local os="$1"

    echo -e "${YELLOW}Configuring system DNS...${NC}"

    case "$os" in
        macos)
            # macOS: Configure networksetup to use local DNS
            # Get the primary network service
            local primary_service
            primary_service=$(networksetup -listnetworkserviceorder | grep -A1 '(1)' | tail -1 | sed 's/.*Device: //' | sed 's/)//')

            if [[ -n "$primary_service" ]]; then
                # Get service name for the device
                local service_name
                service_name=$(networksetup -listnetworkserviceorder | grep -B1 "$primary_service" | head -1 | sed 's/([0-9]*) //')

                if [[ -n "$service_name" ]]; then
                    echo "Configuring DNS for: $service_name"
                    networksetup -setdnsservers "$service_name" 127.0.0.1
                fi
            fi

            # Also set up resolver for fallback
            mkdir -p /etc/resolver
            ;;
        debian|fedora|arch|suse)
            # Linux: Check if systemd-resolved is running
            if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
                # Disable systemd-resolved stub listener
                mkdir -p /etc/systemd/resolved.conf.d/
                cat > /etc/systemd/resolved.conf.d/blink.conf << 'EOF'
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF
                systemctl restart systemd-resolved

                # Point resolv.conf to dnsmasq
                rm -f /etc/resolv.conf
                echo "nameserver 127.0.0.1" > /etc/resolv.conf
            else
                # Direct resolv.conf modification
                if [[ -L /etc/resolv.conf ]]; then
                    rm /etc/resolv.conf
                fi
                echo "nameserver 127.0.0.1" > /etc/resolv.conf
                # Make it immutable to prevent NetworkManager from overwriting
                chattr +i /etc/resolv.conf 2>/dev/null || true
            fi
            ;;
    esac

    echo -e "${GREEN}System DNS configured${NC}"
}

# Start dnsmasq service
start_dnsmasq() {
    local os="$1"

    echo -e "${YELLOW}Starting dnsmasq service...${NC}"

    case "$os" in
        macos)
            # Stop any existing dnsmasq first
            brew services stop dnsmasq 2>/dev/null || true
            sudo brew services start dnsmasq
            ;;
        *)
            systemctl enable dnsmasq
            systemctl restart dnsmasq
            ;;
    esac

    echo -e "${GREEN}dnsmasq started${NC}"
}

# Install blink CLI
install_blink() {
    echo -e "${YELLOW}Installing blink CLI...${NC}"

    cp "$SCRIPT_DIR/blink" /usr/local/bin/blink
    chmod +x /usr/local/bin/blink

    echo -e "${GREEN}blink installed to /usr/local/bin/blink${NC}"
}

# Verify installation
verify_installation() {
    echo ""
    echo -e "${YELLOW}Verifying installation...${NC}"

    local errors=0

    # Check dnsmasq is running
    if pgrep -x dnsmasq > /dev/null; then
        echo -e "  ${GREEN}✓${NC} dnsmasq is running"
    else
        echo -e "  ${RED}✗${NC} dnsmasq is not running"
        errors=$((errors + 1))
    fi

    # Check blink is installed
    if command -v blink &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} blink CLI is installed"
    else
        echo -e "  ${RED}✗${NC} blink CLI not found in PATH"
        errors=$((errors + 1))
    fi

    # Check DNS resolution works
    if nslookup google.com 127.0.0.1 &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} DNS resolution working"
    else
        echo -e "  ${RED}✗${NC} DNS resolution failed"
        errors=$((errors + 1))
    fi

    return $errors
}

# Main installation
main() {
    local os
    os=$(detect_os)

    echo "Detected OS: $os"
    echo ""

    if [[ "$os" == "unknown" ]]; then
        echo -e "${RED}Error: Could not detect OS${NC}"
        echo "Supported: macOS, Ubuntu/Debian, Fedora/RHEL, Arch Linux, openSUSE"
        exit 1
    fi

    check_privileges

    # Check if dnsmasq is already installed
    if command -v dnsmasq &> /dev/null; then
        echo -e "${GREEN}dnsmasq already installed${NC}"
    else
        install_dnsmasq "$os"
    fi

    configure_dnsmasq "$os"
    configure_system_dns "$os"
    start_dnsmasq "$os"
    install_blink

    echo ""
    if verify_installation; then
        echo ""
        echo -e "${GREEN}=== Installation Complete ===${NC}"
        echo ""
        echo "Usage:"
        echo "  sudo blink linkedin.com        # Block permanently"
        echo "  sudo blink linkedin.com 25m    # Block for 25 minutes"
        echo "  sudo blink -u linkedin.com     # Unblock"
        echo "  blink -l                       # List blocked domains"
    else
        echo ""
        echo -e "${RED}=== Installation had errors ===${NC}"
        echo "Please check the messages above and try again"
        exit 1
    fi
}

main "$@"
