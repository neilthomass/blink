# blink

Easily block websites from terminal. Discovers real subdomains (via [Sublist3r](https://github.com/aboul3la/Sublist3r)) and writes them to `/etc/hosts`. Hard lock by default - solve math problems to unblock.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/neilthomass/blink/main/install.sh | bash
```

## Usage

```bash
blink                          # Show blocked domains
blink youtube.com              # Toggle block (hard lock, prompts for sudo)
blink -s youtube.com           # Toggle block (soft lock)
blink --setup                  # Set math difficulty
```

## Math Difficulty

```bash
blink --setup
```

- Times Tables (7 × 8)
- 2x2 (23 × 47)
- 3x2 (234 × 56)
- 3x3 (234 × 567)

Get one wrong, start over.

## Uninstall

```bash
blink uninstall
```
