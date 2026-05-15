#!/bin/bash

set -e

python3 -m venv .venv
source .venv/bin/activate

pip3 install -r requirements.txt

pip3 install t-tech-investments --index-url https://opensource.tbank.ru/api/v4/projects/238/packages/pypi/simple

echo "Иногда обновляйте список тикеров запуская api_get_valid_options"

python3 main.py
