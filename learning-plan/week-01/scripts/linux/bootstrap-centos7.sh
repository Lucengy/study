#!/usr/bin/env bash
set -euo pipefail

if [[ ! -r /etc/centos-release ]] || ! grep -q 'CentOS Linux release 7' /etc/centos-release; then
  echo "This helper is intended for CentOS Linux 7.x." >&2
  exit 1
fi

echo "Installing the Week 1 toolchain. This script does not modify yum repositories or firewall rules."
sudo yum install -y git java-11-openjdk-devel curl unzip openssh-clients chrony

java_home="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
echo "Detected JAVA_HOME=${java_home}"

profile_file="${HOME}/.ratis-study-env"
cat > "${profile_file}" <<EOF
export JAVA_HOME=${java_home}
export PATH=\$JAVA_HOME/bin:\$PATH
export LANG=en_US.UTF-8
EOF

if ! grep -qF '. "$HOME/.ratis-study-env"' "${HOME}/.bashrc"; then
  echo '. "$HOME/.ratis-study-env"' >> "${HOME}/.bashrc"
fi

# shellcheck disable=SC1090
source "${profile_file}"
echo "Toolchain installed. Open a new shell, then run check-study-environment.sh."
java -version
git --version

