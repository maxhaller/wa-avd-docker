#!/usr/bin/env bash
set -Eeuo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_file="${project_dir}/.env"
desktop_user="${1:-avd}"

if [[ -e "${env_file}" ]]; then
    printf 'Refusing to overwrite %s. Remove it explicitly to rotate credentials.\n' "${env_file}" >&2
    exit 1
fi

if [[ ! "${desktop_user}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || [[ "${desktop_user}" == "root" ]]; then
    printf 'Desktop username must be a non-root Linux username (lowercase, up to 32 characters).\n' >&2
    exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
    printf 'OpenSSL is required to generate credentials.\n' >&2
    exit 1
fi

umask 077
desktop_password="$(openssl rand -hex 24)"
http_password="$(openssl rand -hex 24)"

# The VNC protocol used by the desktop image accepts at most eight characters.
# It remains behind both HTTP authentication and the loopback-only SSH tunnel.
vnc_password="$(openssl rand -hex 4)"

{
    printf 'DESKTOP_USER=%s\n' "${desktop_user}"
    printf 'DESKTOP_PASSWORD=%s\n' "${desktop_password}"
    printf 'HTTP_PASSWORD=%s\n' "${http_password}"
    printf 'VNC_PASSWORD=%s\n' "${vnc_password}"
} > "${env_file}"

printf 'Created %s with a non-root desktop user and random credentials.\n' "${env_file}"
printf 'The file is ignored by Git. Keep it private and back it up securely.\n'
