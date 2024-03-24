// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface ILock {
    function getTotalOnus() external view returns (uint256);
    function notifyAmount(uint256 amount) external;
}
