// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.22;

contract PeepsDeployer {
    address public immutable PEEPS;
    address public immutable LOCK;
    address public immutable WETH;
    address public immutable FACTORY;
    address public immutable PAIR;

    constructor(address peeps, address lock, address weth, address factory) {
        PEEPS = peeps;
        LOCK = lock;
        WETH = weth;
        FACTORY = factory;
        PAIR = pairFor(factory, peeps, weth);
    }

    function deploy() external {

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
