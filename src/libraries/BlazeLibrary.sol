// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.22;

library BlazeLibrary {
    uint256 internal constant K = 420e18;
    uint256 internal constant X0 = 69e17;
    uint256 internal constant WAD = 1e18;

    // f(x) = 420/(x + 6.9)
    function getOnus(uint256 totalOnus, uint256 onusableAmount) internal pure returns (uint256) {
        unchecked {
            return K * onusableAmount / (totalOnus + X0) / WAD;
        }
    }
}
