// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

contract LockMock {
    uint256 private onus;

    function setOnus(uint256 onus_) external {
        onus = onus_;
    }

    function getTotalOnus() external view returns (uint256) {
        return onus;
    }

    function notifyAmount(uint256 amount) external {
        onus += amount;
    }
}
