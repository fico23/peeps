// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {Peeps} from "../src/Peeps.sol";
import {WETH} from "solady/tokens/WETH.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {Lock} from "../src/Lock.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";
import {Deployer} from "../src/Deployer.sol";
import {Create2} from "openzeppelin/utils/Create2.sol";

contract DeployerInternal {
    address public immutable PEEPS;
    address public immutable LOCK;
    address public immutable FACTORY;

    constructor(address factory) {
        FACTORY = factory;
        PEEPS = Create2.computeAddress(bytes32(0), keccak256(type(PeepsInternal).creationCode));
        LOCK = Create2.computeAddress(bytes32(0), keccak256(type(Lock).creationCode));
    }

    function deploy() external {
        Create2.deploy(0, bytes32(0), type(PeepsInternal).creationCode);
        Create2.deploy(0, bytes32(0), type(Lock).creationCode);
    }

    function getImmutables() external view returns (address, address, address, address, address) {
        return (address(0), address(0), address(1), FACTORY, address(0));
    }
}

contract PeepsInternal is Peeps {
    function updateBalanceInfo(address addr, uint256 paid, uint256 amount) external {
        return _updateBalanceInfo(addr, paid, amount);
    }

    function getOnus(uint256 totalOnus, uint256 onusableAmount) external pure returns (uint256) {
        return _getOnus(totalOnus, onusableAmount);
    }
}

contract PeepsTest is Test {
    Peeps peeps;
    WETH weth;
    IUniswapV2Factory v2Factory;
    IUniswapV2Router02 v2Router;
    IUniswapV2Pair v2Pair;
    Lock lock;

    address[] internal pathBuy;
    address[] internal pathSell;

    uint256 private constant ETH_LIQUIDITY = 1 ether;
    uint256 private constant BUY_AMOUNT = 0.1 ether;
    address private constant REVENUE_WALLET = address(0xbabe);
    uint96 private constant TOTAL_SUPPLY = type(uint96).max;
    uint256 public constant UNI_MINIMUM_LIQUIDITY = 10 ** 3;
    address private constant ALICE = address(0x1234);
    address private constant BOB = address(0x1233);
    address private constant EVE = address(0x1232);
    address private constant MALLORY = address(0x1231);
    uint256 internal constant WAD = 1e18;
    address private constant DEPLOYER_ADDRESS = 0x29C945F528487655BD6315a198417b7f27FbfE1f;
    bytes32 private constant LOCK_SALT = 0x794b5e2e754365de50fddce65a41a9504034eeb3c8e1fe2f960738932a1bd9f4;
    bytes32 private constant PEEPS_SALT = 0xd2d20c58bc613be2b41b06f8f2fe0c6546f851043dd860585efadd44efae992b;
    uint256 internal constant INITIAL_BUY_AMOUNT = 7182911523753891477745141264;
    uint256 internal constant INITIAL_PEEPS_RESERVE = TOTAL_SUPPLY - INITIAL_BUY_AMOUNT;

    uint256 internal constant K = 420e28;
    uint256 internal constant X0 = 69e17;
    uint256 internal constant ONUS_CAP = 420 ether;
    uint256 internal constant ONUS_PRECISION = 1e12;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function setUp() public {
        weth = new WETH();
        (v2Factory, v2Router) = _deployUniswap(address(weth));

        deployCodeTo("Deployer.sol", abi.encode(weth, v2Factory, PEEPS_SALT, LOCK_SALT), DEPLOYER_ADDRESS);

        Deployer(DEPLOYER_ADDRESS).deploy{value: ETH_LIQUIDITY + BUY_AMOUNT}();

        (address peeps_, address lock_,,,) = Deployer(DEPLOYER_ADDRESS).getImmutables();
        peeps = Peeps(peeps_);
        lock = Lock(lock_);

        v2Pair = IUniswapV2Pair(v2Factory.getPair(address(peeps), address(weth)));

        pathBuy.push(address(weth));
        pathBuy.push(address(peeps));

        pathSell.push(address(peeps));
        pathSell.push(address(weth));

        vm.label(address(lock), "LOCK");
        vm.label(address(weth), "WETH");
        vm.label(address(v2Factory), "UNI_FACTORY");
        vm.label(address(v2Router), "UNI_ROUTER");
        vm.label(address(v2Pair), "UNI_PAIR");
        vm.label(address(peeps), "PEEPS");
        vm.label(DEPLOYER_ADDRESS, "DEPLOYER");
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
        DeployerInternal deployerInternal = new DeployerInternal(address(v2Factory));
        deployerInternal.deploy();
        PeepsInternal peepsInternal = PeepsInternal(deployerInternal.PEEPS());

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
        assertEq(peeps.balanceOf(address(lock)), INITIAL_BUY_AMOUNT);
        assertEq(peeps.balanceOf(address(v2Pair)), TOTAL_SUPPLY - INITIAL_BUY_AMOUNT);
    }

    function testGetOnus(uint72 totalOnus, uint256 onusableAmount) public {
        DeployerInternal deployerInternal = new DeployerInternal(address(v2Factory));
        deployerInternal.deploy();
        PeepsInternal peepsInternal = PeepsInternal(deployerInternal.PEEPS());

        onusableAmount = bound(onusableAmount, 1e5, TOTAL_SUPPLY);

        uint256 onus = peepsInternal.getOnus(totalOnus, onusableAmount);

        assertTrue(onus < onusableAmount);
        assertTrue(onus * WAD / onusableAmount < 60869565218e7); // max onus is 60.869565217%
        if (totalOnus > ONUS_CAP) {
            assertTrue(onus == 0);
        } else {
            assertTrue(onus > 0);
        }
    }

    function testBuy(uint256 amountEth) public {
        amountEth = bound(amountEth, 10, ETH_LIQUIDITY);

        uint256 expectedAmountOut = _getAmountOutPeeps(amountEth);
        _buy(ALICE, amountEth);

        assertEq(peeps.balanceOf(ALICE), expectedAmountOut);

        (uint256 paid, uint256 amount) = peeps.readBalanceInfo(ALICE);
        assertEq(paid, amountEth * WAD);
        assertEq(amount, expectedAmountOut);
    }

    function testBuyAndTransfer(uint256 amountEth, uint8 percentageTransfer) public {
        amountEth = bound(amountEth, 10, ETH_LIQUIDITY);
        percentageTransfer = uint8(bound(percentageTransfer, 1, type(uint8).max));

        uint256 boughtAmount = _getAmountOutPeeps(amountEth);
        _buy(ALICE, amountEth);
        assertEq(peeps.balanceOf(ALICE), boughtAmount);

        uint256 transferAmount = boughtAmount * percentageTransfer / type(uint8).max;
        uint256 initialPaidAmount = amountEth * WAD;

        vm.prank(ALICE);
        vm.expectEmit(true, true, false, true, address(peeps));
        emit Transfer(ALICE, BOB, transferAmount);
        peeps.transfer(BOB, transferAmount);

        uint256 transferedPaidAmount = initialPaidAmount * transferAmount / boughtAmount;

        assertEq(peeps.balanceOf(ALICE), boughtAmount - transferAmount);
        assertEq(peeps.balanceOf(BOB), transferAmount);

        (uint256 alicePaid, uint256 aliceAmount) = peeps.readBalanceInfo(ALICE);
        assertEq(alicePaid, initialPaidAmount - transferedPaidAmount);
        assertEq(aliceAmount, boughtAmount - transferAmount);

        (uint256 bobPaid, uint256 bobAmount) = peeps.readBalanceInfo(BOB);
        assertEq(bobPaid, transferedPaidAmount);
        assertEq(bobAmount, transferAmount);

        assertEq(alicePaid + bobPaid, amountEth * WAD);
    }

    function testBuyAndSell(uint256 amountEth, uint8 percentageSell) public {
        amountEth = bound(amountEth, 1000, ETH_LIQUIDITY);
        percentageSell = uint8(bound(percentageSell, 10, type(uint8).max));

        uint256 boughtAmount = _getAmountOutPeeps(amountEth);
        _buy(ALICE, amountEth);
        assertEq(peeps.balanceOf(ALICE), boughtAmount);
        assertEq(peeps.balanceOf(address(v2Pair)), INITIAL_PEEPS_RESERVE - boughtAmount);

        uint256 sellAmount = boughtAmount * percentageSell / type(uint8).max;
        uint256 initialPaidAmount = amountEth * WAD;

        _sell(ALICE, sellAmount);

        assertEq(peeps.balanceOf(ALICE), boughtAmount - sellAmount);
        assertEq(weth.balanceOf(address(lock)), 0); // no tax since no profit
        assertEq(peeps.balanceOf(address(v2Pair)), INITIAL_PEEPS_RESERVE - boughtAmount + sellAmount);

        (uint256 alicePaid, uint256 aliceAmount) = peeps.readBalanceInfo(ALICE);
        assertEq(alicePaid, initialPaidAmount - initialPaidAmount * sellAmount / boughtAmount);
        assertEq(aliceAmount, boughtAmount - sellAmount);
    }

    function testBuyAndSellWithProfit(uint256 amountEth, uint8 percentageSell) public {
        uint256 bobBuyAmount = 0.1 ether;
        amountEth = bound(amountEth, 1000, ETH_LIQUIDITY - bobBuyAmount);
        percentageSell = uint8(bound(percentageSell, 10, type(uint8).max));

        uint256 boughtAmount = _getAmountOutPeeps(amountEth);
        _buy(ALICE, amountEth);

        uint256 bobBoughtAmount = _getAmountOutPeeps(bobBuyAmount);
        _buy(BOB, bobBuyAmount); // raise price

        uint256 sellAmount = boughtAmount * percentageSell / type(uint8).max;
        uint256 initialPaidAmount = amountEth * WAD;

        uint256 expectedOnus = _getOnus(0, sellAmount);
        uint256 onusWorthEth = _getAmountOutEth(expectedOnus);

        _sell(ALICE, sellAmount);

        assertEq(peeps.balanceOf(ALICE), boughtAmount - sellAmount);
        assertEq(weth.balanceOf(address(lock)), onusWorthEth); // taxed on profit
        assertEq(peeps.balanceOf(address(v2Pair)), INITIAL_PEEPS_RESERVE - boughtAmount - bobBoughtAmount + sellAmount);

        (uint256 alicePaid, uint256 aliceAmount) = peeps.readBalanceInfo(ALICE);
        assertEq(alicePaid, initialPaidAmount - initialPaidAmount * sellAmount / boughtAmount);
        assertEq(aliceAmount, boughtAmount - sellAmount);
    }

    function testBuyAndSellWithLoss(uint256 amountEth, uint8 percentageSell) public {
        uint256 bobBuyAmount = 0.1 ether;
        amountEth = bound(amountEth, 1000, ETH_LIQUIDITY - bobBuyAmount);
        percentageSell = uint8(bound(percentageSell, 10, type(uint8).max));

        uint256 bobBoughtAmount = _getAmountOutPeeps(bobBuyAmount);
        _buy(BOB, bobBuyAmount); // raise price

        uint256 boughtAmount = _getAmountOutPeeps(amountEth);
        _buy(ALICE, amountEth);

        _sell(BOB, bobBoughtAmount);

        uint256 sellAmount = boughtAmount * percentageSell / type(uint8).max;
        uint256 initialPaidAmount = amountEth * WAD;

        uint256 onusBefore = weth.balanceOf(address(lock));

        _sell(ALICE, sellAmount);

        assertEq(peeps.balanceOf(ALICE), boughtAmount - sellAmount);
        assertEq(weth.balanceOf(address(lock)), onusBefore); // no tax since no profit
        assertEq(peeps.balanceOf(address(v2Pair)), INITIAL_PEEPS_RESERVE - boughtAmount + sellAmount);

        (uint256 alicePaid, uint256 aliceAmount) = peeps.readBalanceInfo(ALICE);
        assertEq(alicePaid, initialPaidAmount - initialPaidAmount * sellAmount / boughtAmount);
        assertEq(aliceAmount, boughtAmount - sellAmount);
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

    function _getAmountOutEth(uint256 amountIn) internal view returns (uint256) {
        (uint256 reserve0, uint256 reserve1,) = v2Pair.getReserves();
        (uint256 reservePeeps, uint256 reserveWeth) =
            address(peeps) < address(weth) ? (reserve0, reserve1) : (reserve1, reserve0);

        return _getAmountOut(amountIn, reservePeeps, reserveWeth);
    }

    function _getAmountOutPeeps(uint256 amountIn) internal view returns (uint256) {
        (uint256 reserve0, uint256 reserve1,) = v2Pair.getReserves();
        (uint256 reservePeeps, uint256 reserveWeth) =
            address(peeps) < address(weth) ? (reserve0, reserve1) : (reserve1, reserve0);

        return _getAmountOut(amountIn, reserveWeth, reservePeeps);
    }

    function _getAmountInEth(uint256 amountOut) internal view returns (uint256) {
        (uint256 reserve0, uint256 reserve1,) = v2Pair.getReserves();
        (uint256 reservePeeps, uint256 reserveWeth) =
            address(peeps) < address(weth) ? (reserve0, reserve1) : (reserve1, reserve0);

        return _getAmountIn(amountOut, reservePeeps, reserveWeth);
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

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    function _getOnus(uint256 totalOnus, uint256 onusableAmount) internal pure returns (uint256) {
        if (totalOnus > ONUS_CAP) return 0;
        unchecked {
            return K * onusableAmount / (totalOnus + X0) / ONUS_PRECISION;
        }
    }
}
