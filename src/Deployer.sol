// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.22;

import {Create2} from "openzeppelin/utils/Create2.sol";
import {Peeps} from "./Peeps.sol";
import {Lock} from "./Lock.sol";

contract Deployer {
    address internal immutable PEEPS;
    address internal immutable LOCK;
    address internal immutable WETH;
    address internal immutable FACTORY;
    address internal immutable PAIR;
    address internal immutable DEPLOYER;

    constructor(address peeps, address lock, address weth, address factory) {
        PEEPS = peeps;
        LOCK = lock;
        WETH = weth;
        FACTORY = factory;
        PAIR = pairFor(factory, peeps, weth);
        DEPLOYER = msg.sender;
    }

    function deploy(bytes32 peepsSalt, bytes32 lockSalt) external {
        Create2.deploy(0, peepsSalt, type(Peeps).creationCode);
        Create2.deploy(0, lockSalt, type(Lock).creationCode);
    }

    function getImmutables() external returns (address, address, address, address, address, address) {
        return (PEEPS, LOCK, WETH, FACTORY, PAIR, DEPLOYER);
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f" // init code hash
                        )
                    )
                )
            )
        );
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }
}
