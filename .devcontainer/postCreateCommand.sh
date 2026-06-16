#!/bin/sh

git submodule update --init --recursive
sudo chown -R "$(whoami)":"$(whoami)" /home/"$(whoami)"/app/.venv
uv sync
