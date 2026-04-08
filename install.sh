#!/usr/bin/env bash
set -euo pipefail

# Blink Installer - Cross-platform installation script
# Installs dnsmasq and configures system for wildcard DNS blocking
# Run WITHOUT sudo: curl ... | bash (will prompt for sudo when needed)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Blink Installer ===${NC}"
echo ""

# Abort if running as root
if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}Error: Don't run this script as root/sudo${NC}"
    echo "Run with: curl -fsSL ... | bash"
    exit 1
fi

# Get sudo upfront and keep it alive
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

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
            sudo apt-get update
            sudo apt-get install -y dnsmasq
            ;;
        fedora)
            sudo dnf install -y dnsmasq
            ;;
        arch)
            sudo pacman -S --noconfirm dnsmasq
            ;;
        suse)
            sudo zypper install -y dnsmasq
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
    sudo mkdir -p /etc/dnsmasq.d

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
            echo "conf-dir=/etc/dnsmasq.d/,*.conf" | sudo tee -a "$dnsmasq_conf" > /dev/null
        fi
    else
        echo "conf-dir=/etc/dnsmasq.d/,*.conf" | sudo tee "$dnsmasq_conf" > /dev/null
    fi

    # Create empty blocklist file
    echo "# Blink blocklist - managed by blink CLI" | sudo tee /etc/dnsmasq.d/blink-blocklist.conf > /dev/null

    # Configure dnsmasq with upstream DNS servers
    sudo tee /etc/dnsmasq.d/blink-config.conf > /dev/null << 'EOF'
# Blink dnsmasq configuration
no-resolv
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
                    sudo networksetup -setdnsservers "$service_name" 127.0.0.1
                fi
            fi

            # Also set up resolver for fallback
            sudo mkdir -p /etc/resolver
            ;;
        debian|fedora|arch|suse)
            # Linux: Check if systemd-resolved is running
            if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
                # Disable systemd-resolved stub listener
                sudo mkdir -p /etc/systemd/resolved.conf.d/
                sudo tee /etc/systemd/resolved.conf.d/blink.conf > /dev/null << 'EOF'
[Resolve]
DNS=127.0.0.1
DNSStubListener=no
EOF
                sudo systemctl restart systemd-resolved

                # Point resolv.conf to dnsmasq
                sudo rm -f /etc/resolv.conf
                echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf > /dev/null
            else
                # Direct resolv.conf modification
                if [[ -L /etc/resolv.conf ]]; then
                    sudo rm /etc/resolv.conf
                fi
                echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf > /dev/null
                # Make it immutable to prevent NetworkManager from overwriting
                sudo chattr +i /etc/resolv.conf 2>/dev/null || true
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
            sudo pkill dnsmasq 2>/dev/null || true
            # Start with sudo for port 53 binding
            sudo /opt/homebrew/opt/dnsmasq/sbin/dnsmasq -C /opt/homebrew/etc/dnsmasq.conf 2>/dev/null || \
            sudo /usr/local/opt/dnsmasq/sbin/dnsmasq -C /usr/local/etc/dnsmasq.conf 2>/dev/null || true
            ;;
        *)
            sudo systemctl enable dnsmasq
            sudo systemctl restart dnsmasq
            ;;
    esac

    echo -e "${GREEN}dnsmasq started${NC}"
}

# Install blink CLI
install_blink() {
    echo -e "${YELLOW}Installing blink CLI...${NC}"

    # Download from GitHub
    sudo curl -fsSL https://raw.githubusercontent.com/neilthomass/blink/main/blink -o /usr/local/bin/blink
    sudo chmod +x /usr/local/bin/blink

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
        echo "  blink                          # Show blocked domains"
        echo "  sudo blink youtube.com         # Toggle block (hard lock)"
        echo "  sudo blink -s youtube.com      # Toggle block (soft lock)"
        echo "  sudo blink --setup             # Set math difficulty"
    else
        echo ""
        echo -e "${RED}=== Installation had errors ===${NC}"
        echo "Please check the messages above and try again"
        exit 1
    fi
}

main "$@"
