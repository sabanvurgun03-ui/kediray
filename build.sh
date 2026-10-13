#!/bin/sh
# KediRay: release dosyalarını üretir ve doğrular (dist/). Ayrıntı: tools/build.py
#   ./build.sh                  # dist/ içine kediray-install.sh, kediray-all.tar.gz, kediray-src.tar.gz, sha256sums
#   ./build.sh --out /tmp/x     # başka klasöre
cd "$(dirname "$0")" && exec python3 tools/build.py "$@"
