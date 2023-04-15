#!/bin/bash

git_folder="$HOME/dev/ade/klipper-cfg/klipper/config/"
dest_folder="$HOME/printer_data/"
secrets_origin="$HOME/.secrets/moonraker.secrets"
secrets_dest="$dest_folder/moonraker.secrets"
echo "creating symlink ${git_folder} -> ${dest_folder}"
ln -sfn "${git_folder}" "${dest_folder}"
echo "creating symlink fro secrets"
ln -sfn "${secrets_origin}" "${secrets_dest}"

