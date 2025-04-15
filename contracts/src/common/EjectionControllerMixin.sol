// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;


abstract contract EjectionControllerMixin {
    error InvalidEjectionController();
    error OnlyEjectionController();

    event EjectionControllerChanged(address oldController, address newController);
}
