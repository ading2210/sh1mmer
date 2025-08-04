#!/bin/bash

set -e

if [ ! "$1" ]; then
  echo "usage: build_complete.sh <board_name>"
  exit 1
fi
if [ "$EUID" != "0" ]; then
  echo "error: this script must be run as root"
fi


board="$1"
base_dir="$(realpath -m $(dirname "$0"))"

shim_url="https://dl.cros.download/files/$board/$board.zip"
shim_dir="$base_dir/shim_downloads"
shim_zip_path="$shim_dir/$board.zip"
shim_path="$shim_dir/$board.bin"

out_path="$shim_dir/sh1mmer_${board}_br0ker.bin"

mkdir -p "$shim_dir"
if [ ! -f "$shim_path" ] && [ ! -f "$shim_zip_path" ]; then
  echo "downloading rma shim"
  if [ "$QUIET" ]; then
    wget -q "$shim_url" -O "$shim_zip_path"
  else
    wget "$shim_url" -O "$shim_zip_path"
  fi
fi
if [ ! -f "$shim_path" ]; then
  echo "extracting rma shim"
  unzip "$shim_zip_path" -d "$shim_dir"
  rm "$shim_zip_path"
fi

if [ ! -d "$base_dir/mounted_payloads/updates/"*"/$board" ]; then
  echo "running update downloader"
  if [ ! -d "$base_dir/.venv" ]; then
    python3 -m venv "$base_dir/.venv"
    source "$base_dir/.venv/bin/activate"
    pip3 install protobuf six
  else
    source "$base_dir/.venv/bin/activate"
  fi
  bash ./update_downloader.sh "$board"
fi

echo "copying original shim"
cp "$shim_path" "$out_path"

echo "running wax.sh"
bash wax.sh -i "$out_path" -s 3G
echo "done! your generated shim is located at $out_path"