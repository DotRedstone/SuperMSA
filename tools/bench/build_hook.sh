#!/bin/bash
# DP-02/V02-bin8：转换器由 make 编译；这里在玩具库上验证 raw 与 bin8 输出一致。
set -euo pipefail
bash tests/test_bin8_smoke.sh
