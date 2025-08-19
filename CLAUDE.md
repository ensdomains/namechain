# Forge/foundry tests

- When running tests they should be run from the contracts/ subfolder.
- See package.json for the test commands.
- When testing for event emission never use vm.expectEmit, always use vm.recordLogs and actually check the logs properly.
- Do not use --via-ir when compiling contracts and tests. If there are Solidity stack too deep errors then fix them through code refactoring.
- When doing vm.prank and vm.expectRevert together for a call, always place the vm.expectRevert call before the vm.prank call.
