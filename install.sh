#!/usr/bin/env bash
set -euo pipefail

# Blink Installer - installs CLI and subdomain discovery dependency
# Run WITHOUT sudo: curl ... | bash (will prompt for sudo when needed)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
SUBDOMAIN_TOOL="${BLINK_SUBDOMAIN_TOOL:-sublist3r}"

if [[ -n "${BLINK_STATE_DIR:-}" ]]; then
    STATE_DIR="$BLINK_STATE_DIR"
else
    STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/blink"
fi

echo -e "${BLUE}=== Blink Installer ===${NC}"
echo ""

if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}Error: Don't run this script as root/sudo${NC}"
    echo "Run with: curl -fsSL ... | bash"
    exit 1
fi

sudo -v
keep_sudo_alive() {
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done
}
keep_sudo_alive 2>/dev/null &
KEEP_ALIVE_PID=$!

trap 'kill "$KEEP_ALIVE_PID" >/dev/null 2>&1 || true' EXIT

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

install_subdomain_tool() {
    local os="$1"

    if [[ "$SUBDOMAIN_TOOL" != "sublist3r" ]]; then
        echo -e "${YELLOW}Custom subdomain tool '$SUBDOMAIN_TOOL' specified. Install it manually if needed.${NC}"
        return
    fi

    if command -v "$SUBDOMAIN_TOOL" >/dev/null 2>&1; then
        echo -e "${GREEN}$SUBDOMAIN_TOOL already installed${NC}"
        return
    fi

    echo -e "${YELLOW}Installing $SUBDOMAIN_TOOL...${NC}"

    if command -v brew >/dev/null 2>&1; then
        if brew install sublist3r; then
            return
        fi
    fi

    if command -v apt-get >/dev/null 2>&1; then
        if sudo apt-get update && sudo apt-get install -y sublist3r; then
            return
        fi
    fi

    if command -v dnf >/dev/null 2>&1; then
        if sudo dnf install -y sublist3r; then
            return
        fi
    fi

    if command -v pacman >/dev/null 2>&1; then
        if sudo pacman -S --noconfirm sublist3r; then
            return
        fi
    fi

    if command -v pipx >/dev/null 2>&1; then
        if pipx install sublist3r; then
            return
        fi
    fi

    local py_exec=""
    if command -v python3 >/dev/null 2>&1; then
        py_exec="python3"
    elif command -v python >/dev/null 2>&1; then
        py_exec="python"
    fi

    if [[ -n "$py_exec" ]] && "$py_exec" -m pip --version >/dev/null 2>&1; then
        if "$py_exec" -m pip install --user --upgrade sublist3r; then
            local user_base
            user_base=$("$py_exec" -c 'import site; print(site.getuserbase())' 2>/dev/null || echo "$HOME/.local")
            local candidate="$user_base/bin/sublist3r"
            if [[ -x "$candidate" ]]; then
                sudo install -m 755 "$candidate" /usr/local/bin/sublist3r
            fi
            if command -v sublist3r >/dev/null 2>&1; then
                return
            fi
        fi
    fi

    echo -e "${RED}Could not automatically install $SUBDOMAIN_TOOL${NC}"
    echo "Install it manually: https://github.com/aboul3la/Sublist3r"
    exit 1
}

install_blink_cli() {
    echo -e "${YELLOW}Installing blink CLI...${NC}"
    sudo curl -fsSL https://raw.githubusercontent.com/neilthomass/blink/main/blink -o /usr/local/bin/blink
    sudo chmod +x /usr/local/bin/blink
    echo -e "${GREEN}blink installed to /usr/local/bin/blink${NC}"
}

prepare_state_dir() {
    mkdir -p "$STATE_DIR"
    touch "$STATE_DIR/domains"
    touch "$STATE_DIR/hardlock"
    if [[ ! -f "$STATE_DIR/config" ]]; then
        echo "MATH_DIFFICULTY=2x2" > "$STATE_DIR/config"
    fi
}

verify_installation() {
    echo ""
    echo -e "${YELLOW}Verifying installation...${NC}"

    if command -v blink >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} blink CLI is installed"
    else
        echo -e "  ${RED}✗${NC} blink CLI missing from PATH"
    fi

    if command -v "$SUBDOMAIN_TOOL" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $SUBDOMAIN_TOOL is installed"
    else
        echo -e "  ${RED}✗${NC} $SUBDOMAIN_TOOL not found"
    fi

    if [[ -f "$STATE_DIR/domains" ]]; then
        echo -e "  ${GREEN}✓${NC} State directory initialized"
    else
        echo -e "  ${RED}✗${NC} State directory missing"
    fi
}

main() {
    local os
    os=$(detect_os)

    install_subdomain_tool "$os"
    install_blink_cli
    prepare_state_dir
    verify_installation

    echo ""
    echo -e "${GREEN}Installation complete${NC}"
    echo "Run 'blink' to view status or 'blink example.com' to toggle blocking."
}

main "$@"
