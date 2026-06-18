#!/bin/bash
#
# install-tools.sh
# Installs: git, figlet (built from source), PostgreSQL client (version 14-18, your choice)
# Supports: Ubuntu, Debian, CentOS, Amazon Linux, Oracle Linux, Rocky Linux, RHEL
#
# Usage:
#   ./install-tools.sh         # prompts interactively for the PostgreSQL version
#   ./install-tools.sh 16      # installs PostgreSQL 16 client, no prompt
#
set -e

# ---------------------------------------------------------------------------
# 1. Detect the OS / distro family
# ---------------------------------------------------------------------------
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID,,}"
    OS_ID_LIKE="${ID_LIKE,,}"
    OS_VERSION_ID="${VERSION_ID}"
else
    echo "Cannot detect OS: /etc/os-release not found." >&2
    exit 1
fi

echo "Detected OS: $OS_ID (version $OS_VERSION_ID)"

DEBIAN_FAMILY="ubuntu debian"
RHEL_FAMILY="rhel centos rocky almalinux ol amzn fedora"

is_in_family() {
    local target="$1"
    local family="$2"
    for item in $family; do
        [[ "$target" == "$item" ]] && return 0
    done
    return 1
}

PKG_FAMILY=""
if is_in_family "$OS_ID" "$DEBIAN_FAMILY"; then
    PKG_FAMILY="debian"
elif is_in_family "$OS_ID" "$RHEL_FAMILY"; then
    PKG_FAMILY="rhel"
else
    # Fall back to ID_LIKE (covers less common derivatives)
    for like in $OS_ID_LIKE; do
        if is_in_family "$like" "$DEBIAN_FAMILY"; then
            PKG_FAMILY="debian"
            break
        elif is_in_family "$like" "$RHEL_FAMILY"; then
            PKG_FAMILY="rhel"
            break
        fi
    done
fi

if [ -z "$PKG_FAMILY" ]; then
    echo "Unsupported or unrecognized OS: $OS_ID" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 1b. Determine which PostgreSQL client version to install (14-18)
#     Accepts it as $1, otherwise prompts interactively.
# ---------------------------------------------------------------------------
SUPPORTED_PG_VERSIONS="14 15 16 17 18"

is_supported_pg_version() {
    local v="$1"
    for sv in $SUPPORTED_PG_VERSIONS; do
        [[ "$v" == "$sv" ]] && return 0
    done
    return 1
}

PG_VERSION="$1"

if [ -n "$PG_VERSION" ]; then
    if ! is_supported_pg_version "$PG_VERSION"; then
        echo "Error: '$PG_VERSION' is not a supported PostgreSQL version. Choose from: $SUPPORTED_PG_VERSIONS" >&2
        exit 1
    fi
else
    # No version passed as an argument -> ask interactively
    while true; do
        read -rp "Which PostgreSQL client version do you want to install? [14-18]: " PG_VERSION
        if is_supported_pg_version "$PG_VERSION"; then
            break
        fi
        echo "Invalid choice. Please enter one of: $SUPPORTED_PG_VERSIONS"
    done
fi

echo "PostgreSQL client version selected: $PG_VERSION"

# ---------------------------------------------------------------------------
# 2. Pick the right package manager within the RHEL family
#    (older CentOS 7 / Amazon Linux 2 only have yum, not dnf)
# ---------------------------------------------------------------------------
if [ "$PKG_FAMILY" = "rhel" ]; then
    if command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
    else
        PKG_MGR="yum"
    fi
fi

NEED_SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        NEED_SUDO="sudo"
    else
        echo "This script must be run as root or with sudo available." >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# 3. Install base build tools + git (needed to compile figlet)
# ---------------------------------------------------------------------------
echo "==> Installing git and build tools..."
if [ "$PKG_FAMILY" = "debian" ]; then
    $NEED_SUDO apt-get update -y
    $NEED_SUDO apt-get install -y git build-essential
else
    $NEED_SUDO $PKG_MGR install -y git make gcc
fi

# ---------------------------------------------------------------------------
# 4. Install Figlet from source
# ---------------------------------------------------------------------------
echo "==> Building figlet from source..."
WORKDIR="$(mktemp -d)"
git clone https://github.com/cmatsuoka/figlet.git "$WORKDIR/figlet"
cd "$WORKDIR/figlet"
make
$NEED_SUDO make install
$NEED_SUDO cp figlet /usr/bin/
cd - >/dev/null
rm -rf "$WORKDIR"

# ---------------------------------------------------------------------------
# 5. Install PostgreSQL client (version chosen above)
# ---------------------------------------------------------------------------
echo "==> Installing PostgreSQL $PG_VERSION client..."

if [ "$PKG_FAMILY" = "rhel" ]; then
    # Map distro to the PGDG EL major version (8, 9, ...)
    case "$OS_VERSION_ID" in
        9*) EL_VER="9" ;;
        8*) EL_VER="8" ;;
        7*) EL_VER="7" ;;
        2)  EL_VER="7" ;;   # Amazon Linux 2 -> use EL7 repo
        2023) EL_VER="9" ;; # Amazon Linux 2023 -> closest is EL9 repo
        *)  EL_VER="9" ;;   # sensible default
    esac

    REPO_RPM="https://download.postgresql.org/pub/repos/yum/reporpms/EL-${EL_VER}-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
    $NEED_SUDO $PKG_MGR install -y "$REPO_RPM"

    # RHEL/CentOS 7 (EL-7) only has PGDG packages up to PostgreSQL 15
    if [ "$EL_VER" = "7" ] && [ "$PG_VERSION" -gt 15 ]; then
        echo "Error: PostgreSQL $PG_VERSION is not available for EL-7 (RHEL/CentOS 7 / Amazon Linux 2)." >&2
        echo "EL-7 only supports PostgreSQL versions up to 15. Choose 14 or 15." >&2
        exit 1
    fi

    # Disable the distro's built-in postgresql module so the PGDG package wins
    if [ "$PKG_MGR" = "dnf" ]; then
        $NEED_SUDO dnf -qy module disable postgresql || true
    fi

    $NEED_SUDO $PKG_MGR install -y "postgresql${PG_VERSION}" --nogpgcheck

elif [ "$PKG_FAMILY" = "debian" ]; then
    # Use the official PGDG APT repo
    DISTRO_CODENAME="${VERSION_CODENAME}"
    $NEED_SUDO apt-get install -y curl ca-certificates gnupg lsb-release

    $NEED_SUDO install -d /usr/share/postgresql-common/pgdg
    $NEED_SUDO curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
        --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc

    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${DISTRO_CODENAME}-pgdg main" \
        | $NEED_SUDO tee /etc/apt/sources.list.d/pgdg.list

    $NEED_SUDO apt-get update -y
    $NEED_SUDO apt-get install -y "postgresql-client-${PG_VERSION}"
fi

# ---------------------------------------------------------------------------
# 6. Verify
# ---------------------------------------------------------------------------
echo "==> Verifying installs..."
git --version || true
figlet "Done!" || echo "figlet installed but not on PATH yet (try a new shell)"
psql --version || true

echo "All done."
