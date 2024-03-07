// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Peeps} from "../src/Peeps.sol";
import {WETH} from "solady/tokens/WETH.sol";

contract PeepsTest is Test {
    Peeps private peeps;
    WETH private weth;

    address constant private REVENUE_WALLET = address(0xbabe);

    function setUp() public {
        weth = new WETH();
        peeps = new Peeps(REVENUE_WALLET, address(weth), );
    }
}
