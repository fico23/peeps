// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface IDeployer {
    function getImmutables() external view returns (address, address, address, address, address, address);
    function notifyAmount(uint256 amount) external;
}
