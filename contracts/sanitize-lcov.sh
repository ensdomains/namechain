# Original script from https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/e91c3100c29d2913d175df4b3d1790d6a057d36e/solidity/coverage.sh

# Filter out node_modules, test, and mock files
lcov \
    --ignore-errors inconsistent \
    --ignore-errors unused \
    --rc lcov_branch_coverage=1 \
    --remove lcov.info \
    --output-file lcov.info \
    "*test*" "*mock*"

