# blink

Easily block websites from terminal. Blocks all subdomains. Hard lock by default - solve math problems to unblock.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/neilthomass/blink/main/install.sh | bash
```

## Usage

```bash
blink                          # Show blocked domains
sudo blink youtube.com         # Toggle block (hard lock)
sudo blink -s youtube.com      # Toggle block (soft lock)
sudo blink --setup             # Set math difficulty
```

## Math Difficulty

```bash
sudo blink --setup
```

- Times Tables (7 × 8)
- 2x2 (23 × 47)
- 3x2 (234 × 56)
- 3x3 (234 × 567)

Get one wrong, start over.

## Uninstall

```bash
sudo blink uninstall
```
