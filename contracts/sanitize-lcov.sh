# Original script from https://github.com/hyperlane-xyz/hyperlane-monorepo/blob/e91c3100c29d2913d175df4b3d1790d6a057d36e/solidity/coverage.sh

# merge files
lcov \
    --ignore-errors inconsistent,unused \
    --rc branch_coverage=1 \
    --add-tracefile "coverage/*.info" \
    --output-file lcov.info

# filter junk
lcov --remove lcov.info "lib/*" "*test*" "*mock*" --output-file lcov.info

# fix source path
sed 's|^SF:src/|SF:/contracts/src/|' lcov.info > lcov.fixed && mv lcov.fixed lcov.info
