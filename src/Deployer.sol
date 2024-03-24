// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.22;

import {CREATE3} from "solady/utils/CREATE3.sol";
import {Peeps} from "./Peeps.sol";
import {Lock} from "./Lock.sol";

contract Deployer {
    constructor(address weth, address v2Factory, uint256 totalSupply, bytes32 lockSalt, address lockAddress, bytes32 peepsSalt) {
        // address lockDeployAddress = CREATE3.
    }
}