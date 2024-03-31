// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.25;

import {Create2} from "openzeppelin/utils/Create2.sol";
import {Peeps} from "./Peeps.sol";
import {Lock} from "./Lock.sol";
import {IWETH} from "v2-periphery/interfaces/IWETH.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";

contract Deployer {
    address internal immutable PEEPS;
    address internal immutable LOCK;
    address internal immutable WETH;
    address internal immutable FACTORY;
    address internal immutable PAIR;
    address internal immutable DEPLOYER;
    bytes32 internal immutable PEEPS_SALT;
    bytes32 internal immutable LOCK_SALT;

    uint256 internal constant TOTAL_SUPPLY = type(uint96).max;
    uint256 internal constant LIQ_AMOUNT = 1 ether;
    uint256 internal constant ETH_BUY_AMOUNT = 0.1 ether;
    uint256 internal constant INITIAL_BUY_AMOUNT = 7182911523753891477745141264;

    constructor(address weth, address factory, bytes32 peepsSalt, bytes32 lockSalt) {
        PEEPS = Create2.computeAddress(peepsSalt, keccak256(type(Peeps).creationCode));
        LOCK = Create2.computeAddress(lockSalt, keccak256(type(Lock).creationCode));
        WETH = weth;
        FACTORY = factory;
        PAIR = pairFor(factory, PEEPS, weth);
        PEEPS_SALT = peepsSalt;
        LOCK_SALT = lockSalt;
        DEPLOYER = msg.sender;
    }

    function deploy() external payable {
        require(msg.sender == DEPLOYER, "YOU'RE NOT HIM");

        Create2.deploy(0, PEEPS_SALT, type(Peeps).creationCode);
        Create2.deploy(0, LOCK_SALT, type(Lock).creationCode);

        IWETH(WETH).deposit{value: msg.value}();

        assert(IWETH(WETH).transfer(address(PAIR), LIQ_AMOUNT));
        IUniswapV2Pair(PAIR).mint(msg.sender);

        assert(IWETH(WETH).transfer(address(PAIR), ETH_BUY_AMOUNT));
        (uint256 amount0Out, uint256 amount1Out) =
            PEEPS > WETH ? (uint256(0), INITIAL_BUY_AMOUNT) : (INITIAL_BUY_AMOUNT, uint256(0));
        IUniswapV2Pair(PAIR).swap(amount0Out, amount1Out, address(this), new bytes(0));

        Peeps(PEEPS).approve(LOCK, INITIAL_BUY_AMOUNT);
        Lock(LOCK).lock(INITIAL_BUY_AMOUNT, DEPLOYER);
    }

    function getImmutables() external view returns (address, address, address, address, address) {
        return (PEEPS, LOCK, WETH, FACTORY, PAIR);
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
