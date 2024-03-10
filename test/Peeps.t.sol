// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Peeps} from "../src/Peeps.sol";
import {WETH} from "solady/tokens/WETH.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {LockMock} from "./mocks/LockMock.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";

contract PeepsInternal is Peeps {
    constructor(address _revenueWallet, address _weth, IUniswapV2Factory _factory, address lock, uint96 _totalSupply)
        Peeps(_revenueWallet, _weth, _factory, lock, _totalSupply)
    {}

    function updateBalanceInfo(address addr, uint256 paid, uint256 amount) external {
        return _updateBalanceInfo(addr, paid, amount);
    }
}

contract PeepsTest is Test {
    Peeps peeps;
    WETH weth;
    IUniswapV2Factory v2Factory;
    IUniswapV2Router02 v2Router;
    IUniswapV2Pair v2Pair;
    LockMock lockMock;

    address[] internal pathBuy;
    address[] internal pathSell;

    uint256 private constant ETH_LIQUIDITY = 1 ether;
    address private constant REVENUE_WALLET = address(0xbabe);
    uint96 private constant TOTAL_SUPPLY = type(uint96).max;
    uint256 public constant UNI_MINIMUM_LIQUIDITY = 10 ** 3;
    address private constant ALICE = address(0x1234);
    address private constant BOB = address(0x1233);
    address private constant EVE = address(0x1232);
    address private constant MALLORY = address(0x1231);

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function setUp() public {
        lockMock = new LockMock();

        weth = new WETH();

        (v2Factory, v2Router) = _deployUniswap(address(weth));

        peeps = new Peeps(REVENUE_WALLET, address(weth), v2Factory, address(lockMock), TOTAL_SUPPLY);

        peeps.approve(address(v2Router), TOTAL_SUPPLY);

        v2Pair = IUniswapV2Pair(v2Factory.getPair(address(peeps), address(weth)));

        pathBuy.push(address(weth));
        pathBuy.push(address(peeps));

        pathSell.push(address(peeps));
        pathSell.push(address(weth));

        vm.label(address(lockMock), "LOCK");
        vm.label(address(weth), "WETH");
        vm.label(address(v2Factory), "UNI_FACTORY");
        vm.label(address(v2Router), "UNI_ROUTER");
        vm.label(address(v2Pair), "UNI_PAIR");
        vm.label(address(peeps), "PEEPS");
        vm.label(ALICE, "ALICE");
        vm.label(BOB, "BOB");
        vm.label(EVE, "EVE");
        vm.label(MALLORY, "MALLORY");

        deal(ALICE, 100 ether);
        deal(BOB, 100 ether);
        deal(EVE, 100 ether);
        deal(MALLORY, 100 ether);
        deal(address(this), 100 ether);
    }

    function testBalancePacking(address addr, uint160 paid, uint96 amount) public {
        PeepsInternal peepsInternal =
            new PeepsInternal(REVENUE_WALLET, address(weth), v2Factory, address(lockMock), TOTAL_SUPPLY);

        peepsInternal.updateBalanceInfo(addr, paid, amount);

        (uint256 actualPaid, uint256 actualAmount) = peepsInternal.readBalanceInfo(addr);

        assertEq(peepsInternal.balanceOf(addr), amount);
        assertEq(actualPaid, paid);
        assertEq(actualAmount, amount);
    }

    function testDeploy() public {
        assertEq(peeps.totalSupply(), TOTAL_SUPPLY);
        assertEq(peeps.balanceOf(address(this)), 0);
        assertEq(peeps.balanceOf(address(peeps)), 0);
        assertEq(peeps.balanceOf(address(v2Pair)), 0);
    }

    function testAddLiqudity(uint112 ethLiquidity) public {
        if (_uniSqrt(uint256(TOTAL_SUPPLY) * ethLiquidity) < UNI_MINIMUM_LIQUIDITY) {
            vm.expectRevert();
            peeps.addLiquidity{value: ethLiquidity}();
            return;
        }

        vm.expectEmit(true, true, false, true, address(peeps));
        emit Transfer(address(0), address(v2Pair), TOTAL_SUPPLY);
        vm.expectEmit(true, true, false, true, address(weth));
        emit Transfer(address(0), address(peeps), ethLiquidity);
        vm.expectEmit(true, true, false, true, address(weth));
        emit Transfer(address(peeps), address(v2Pair), ethLiquidity);

        vm.deal(address(this), ethLiquidity);
        peeps.addLiquidity{value: ethLiquidity}();

        assertEq(peeps.balanceOf(address(v2Pair)), TOTAL_SUPPLY);

        (uint256 reserve0, uint256 reserve1,) = v2Pair.getReserves();
        (uint256 reserveToken, uint256 reserveWETH) =
            address(peeps) < address(weth) ? (reserve0, reserve1) : (reserve1, reserve0);

        assertEq(reserveToken, TOTAL_SUPPLY);
        assertEq(reserveWETH, ethLiquidity);
    }

    function testAddLiquidityUnauthorized() public {
        vm.prank(ALICE);

        vm.expectRevert(Peeps.Unauthorized.selector);
        peeps.addLiquidity{value: ETH_LIQUIDITY}();
    }

    function testAddLiquidityAlreadyAdded() public {
        peeps.addLiquidity{value: ETH_LIQUIDITY}();
        vm.expectRevert(Peeps.LiquidityAlreadyAdded.selector);
        peeps.addLiquidity{value: ETH_LIQUIDITY}();
    }

    function testBuy(uint256 amountEth) public {
        amountEth = bound(amountEth, 1, ETH_LIQUIDITY);

        peeps.addLiquidity{value: ETH_LIQUIDITY}();

        uint256 expectedAmountOut = _getAmountOutPeeps(amountEth);
        _buy(ALICE, amountEth);

        assertEq(peeps.balanceOf(ALICE), expectedAmountOut);

        (uint256 paid, uint256 amount) = peeps.readBalanceInfo(ALICE);
        assertEq(paid, amountEth);
        assertEq(amount, expectedAmountOut);
    }

    function testBuyAndTransfer(uint256 amountEth, uint8 percentageTransfer) public {
        amountEth = bound(amountEth, 1, ETH_LIQUIDITY);
        percentageTransfer = uint8(bound(percentageTransfer, 1, type(uint8).max));

        peeps.addLiquidity{value: ETH_LIQUIDITY}();

        uint256 expectedAmountOut = _getAmountOutPeeps(amountEth);
        _buy(ALICE, amountEth);
        assertEq(peeps.balanceOf(ALICE), expectedAmountOut);

        uint256 transferAmount = expectedAmountOut * percentageTransfer / type(uint8).max;

        vm.prank(ALICE);
        vm.expectEmit(true, true, false, true, address(peeps));
        emit Transfer(ALICE, BOB, transferAmount);
        peeps.transfer(BOB, transferAmount);

        assertEq(peeps.balanceOf(ALICE), expectedAmountOut - transferAmount);
        assertEq(peeps.balanceOf(BOB), transferAmount);

        (uint256 alicePaid, uint256 aliceAmount) = peeps.readBalanceInfo(ALICE);
        assertEq(alicePaid, amountEth - amountEth * transferAmount / expectedAmountOut);
        assertEq(aliceAmount, expectedAmountOut - transferAmount);

        (uint256 bobPaid, uint256 bobAmount) = peeps.readBalanceInfo(BOB);
        assertEq(bobPaid, amountEth * transferAmount / expectedAmountOut);
        assertEq(bobAmount, transferAmount);

        assertEq(alicePaid + bobPaid, amountEth);
    }

    function _deployUniswap(address weth_)
        internal
        returns (IUniswapV2Factory v2Factory_, IUniswapV2Router02 v2Router_)
    {
        // deploy uniswap factory & router from bytecodes, to avoid resolving different solidity versions
        bytes memory args1 = abi.encode(address(this));
        bytes memory bytecode1 = abi.encodePacked(vm.getCode("artifacts/UniswapV2Factory.json"), args1);
        address factoryAddress;
        assembly {
            factoryAddress := create(0, add(bytecode1, 0x20), mload(bytecode1))
        }
        v2Factory_ = IUniswapV2Factory(factoryAddress);

        bytes memory args2 = abi.encode(address(v2Factory_), weth_);
        bytes memory bytecode2 = abi.encodePacked(vm.getCode("artifacts/UniswapV2Router02.json"), args2);
        address routerAddress;
        assembly {
            routerAddress := create(0, add(bytecode2, 0x20), mload(bytecode2))
        }
        v2Router_ = IUniswapV2Router02(routerAddress);
    }

    function _uniSqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _buy(address from, uint256 amountEth) internal {
        deal(from, amountEth);

        vm.prank(from);
        v2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountEth}(1, pathBuy, from, block.timestamp);
    }

    function _sell(address from, uint256 amountPeeps) internal {
        vm.prank(from);
        peeps.approve(address(v2Router), amountPeeps);

        vm.prank(from);
        v2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(amountPeeps, 1, pathSell, from, block.timestamp);
    }

    function _getAmountOutEth(uint256 amountIn) internal view returns (uint256 amountOut) {
        (uint256 reserve0, uint256 reserve1,) = v2Pair.getReserves();
        (uint256 reservePeeps, uint256 reserveWeth) =
            address(peeps) < address(weth) ? (reserve0, reserve1) : (reserve1, reserve0);

        return _getAmountOut(amountIn, reservePeeps, reserveWeth);
    }

    function _getAmountOutPeeps(uint256 amountIn) internal view returns (uint256 amountOut) {
        (uint256 reserve0, uint256 reserve1,) = v2Pair.getReserves();
        (uint256 reservePeeps, uint256 reserveWeth) =
            address(peeps) < address(weth) ? (reserve0, reserve1) : (reserve1, reserve0);

        return _getAmountOut(amountIn, reserveWeth, reservePeeps);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
