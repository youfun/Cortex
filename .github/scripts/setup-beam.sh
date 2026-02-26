#!/bin/bash
set -e

### ====== Version Configuration ======
OTP_VERSION="${OTP_VERSION:-28.3.1}"
OTP_SHORT="${OTP_SHORT:-28}"
ELIXIR_VERSION="${ELIXIR_VERSION:-1.19.5}"
UBUNTU_VERSION="${UBUNTU_VERSION:-22.04}"

### ====== Derived Variables ======
ERLANG_DIR="$HOME/erlang_${OTP_SHORT}"
ELIXIR_DIR="$HOME/elixir_otp${OTP_SHORT}"

OTP_TAR="OTP-${OTP_VERSION}.tar.gz"
OTP_URL="https://builds.hex.pm/builds/otp/ubuntu-${UBUNTU_VERSION}/${OTP_TAR}"

ELIXIR_ZIP="elixir-otp-${OTP_SHORT}.zip"
ELIXIR_URL="https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/${ELIXIR_ZIP}"

### ====== Install Erlang ======
if [ ! -d "$ERLANG_DIR" ]; then
    echo "Installing Erlang OTP ${OTP_VERSION}..."
    mkdir -p "$ERLANG_DIR"
    wget -q "$OTP_URL" -O otp.tar.gz
    tar -xzf otp.tar.gz -C "$ERLANG_DIR" --strip-components=1
    rm otp.tar.gz
    if [ -f "$ERLANG_DIR/Install" ]; then
        "$ERLANG_DIR/Install" -minimal "$ERLANG_DIR"
    fi
    echo "Erlang ${OTP_VERSION} installed to ${ERLANG_DIR}"
else
    echo "Erlang ${OTP_VERSION} already installed at ${ERLANG_DIR}"
fi

### ====== Install Elixir ======
if [ ! -d "$ELIXIR_DIR" ]; then
    echo "Installing Elixir ${ELIXIR_VERSION} (OTP ${OTP_SHORT})..."
    mkdir -p "$ELIXIR_DIR"
    wget -q "$ELIXIR_URL" -O elixir.zip
    unzip -q -o elixir.zip -d "$ELIXIR_DIR"
    rm elixir.zip
    echo "Elixir ${ELIXIR_VERSION} installed to ${ELIXIR_DIR}"
else
    echo "Elixir ${ELIXIR_VERSION} already installed at ${ELIXIR_DIR}"
fi

### ====== Export to GitHub Actions PATH ======
if [ -n "$GITHUB_PATH" ]; then
    echo "$ELIXIR_DIR/bin" >> "$GITHUB_PATH"
    echo "$ERLANG_DIR/bin" >> "$GITHUB_PATH"
    echo "Added to GitHub Actions PATH"
fi

### ====== Export to current shell ======
export PATH="$ELIXIR_DIR/bin:$ERLANG_DIR/bin:$PATH"

### ====== Verify Installation ======
echo ""
echo "=== Verification ==="
"$ERLANG_DIR/bin/erl" -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
"$ELIXIR_DIR/bin/elixir" --version

echo ""
echo "Environment setup complete."
