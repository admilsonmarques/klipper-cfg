#!/bin/bash

git_folder="../klipper/config/"
dest_folder="$HOME/printer_data/"
echo "creating symlink ${git_folder} -> ${dest_folder}"
ln -sfn  "${dest_folder}" "${git_folder}"


