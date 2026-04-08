# blink

Block websites and all subdomains. Hard lock by default - solve math problems to unlock.

## Install

```bash
sudo ./install.sh
```

## Usage

```bash
sudo blink linkedin.com        # Block (hard lock)
sudo blink linkedin.com 25m    # Block for 25 minutes
sudo blink -s linkedin.com     # Soft lock (no math)
sudo blink -u linkedin.com     # Unblock (math challenge)
sudo blink --setup             # Set math difficulty
blink -l                       # List blocked
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
