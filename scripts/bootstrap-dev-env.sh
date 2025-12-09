#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${REPO_ROOT}/tools"

OS="$(uname -s)"
ARCH="$(uname -m)"

if [[ "${OS}" != "Darwin" || "${ARCH}" != "arm64" ]]; then
  echo "This bootstrap script currently supports macOS arm64 environments only." >&2
  exit 1
fi

mkdir -p "${TOOLS_DIR}"

install_node() {
  local version="${NODE_VERSION:-20.11.1}"
  local target_dir="${TOOLS_DIR}/node"

  if [[ -x "${target_dir}/bin/node" ]]; then
    echo "Node.js ${version} already installed at ${target_dir}"
    return
  fi

  echo "Installing Node.js ${version}..."
  local tarball="node-v${version}-darwin-arm64.tar.gz"
  curl -fsSL "https://nodejs.org/dist/v${version}/${tarball}" -o "${TOOLS_DIR}/${tarball}"
  tar -xf "${TOOLS_DIR}/${tarball}" -C "${TOOLS_DIR}"
  mv "${TOOLS_DIR}/node-v${version}-darwin-arm64" "${target_dir}"
  rm "${TOOLS_DIR}/${tarball}"
  echo "Node.js ${version} installed to ${target_dir}"
}

install_flutter() {
  local version="${FLUTTER_VERSION:-3.24.2}"
  local target_dir="${TOOLS_DIR}/flutter"

  if [[ -x "${target_dir}/bin/flutter" ]]; then
    echo "Flutter ${version} already installed at ${target_dir}"
    return
  fi

  echo "Installing Flutter ${version}..."
  local zip="flutter_macos_arm64_${version}-stable.zip"
  curl -L "https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/${zip}" -o "${TOOLS_DIR}/${zip}"
  unzip -q "${TOOLS_DIR}/${zip}" -d "${TOOLS_DIR}"
  mv "${TOOLS_DIR}/flutter" "${target_dir}"
  rm "${TOOLS_DIR}/${zip}"
  "${target_dir}/bin/flutter" config --no-analytics
  echo "Flutter ${version} installed to ${target_dir}"
}

install_pyenv_python() {
  local python_version="${PYTHON_VERSION:-3.11.9}"
  local pyenv_root="${TOOLS_DIR}/pyenv"

  if [[ ! -d "${pyenv_root}" ]]; then
    echo "Installing pyenv..."
    git clone https://github.com/pyenv/pyenv.git "${pyenv_root}"
  fi

  export PYENV_ROOT="${pyenv_root}"
  export PATH="${PYENV_ROOT}/bin:${PATH}"

  if [[ ! -d "${PYENV_ROOT}/versions/${python_version}" ]]; then
    echo "Installing Python ${python_version} via pyenv (this may take a few minutes)..."
    pyenv install "${python_version}"
  else
    echo "Python ${python_version} already installed in pyenv."
  fi
}

main() {
  install_node
  install_flutter
  install_pyenv_python

  cat <<EOF

Bootstrap complete!

Add the following exports to your shell or use them per-command:

  export PATH="${TOOLS_DIR}/node/bin:\$PATH"
  export PATH="${TOOLS_DIR}/flutter/bin:\$PATH"
  export PYENV_ROOT="${TOOLS_DIR}/pyenv"
  export PATH="\$PYENV_ROOT/bin:\$PATH"
  export PATH="\$PYENV_ROOT/shims:\$PATH"

Run poetry using the managed Python:

  PATH="\$PYENV_ROOT/bin:\$PATH" poetry env use "\$PYENV_ROOT/versions/${PYTHON_VERSION:-3.11.9}/bin/python3"

EOF
}

main "$@"
