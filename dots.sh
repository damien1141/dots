# dots.sh — commit this next to install_dots.sh
#!/usr/bin/env bash
set -euo pipefail
bash -n "$(dirname "$0")/install_dots.sh" || { echo "parse check failed — do not run" >&2; exit 1; }
chmod +x install_dots.sh
exec "$(dirname "$0")/install_dots.sh" "$@"
