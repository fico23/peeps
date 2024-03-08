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

    function updateBalanceInfo(address addr, uint256 bought, uint256 paid, uint256 amount) external {
        return _updateBalanceInfo(addr, bought, paid, amount);
    }

    function readBalanceInfo(address addr) external view returns (uint256, uint256, uint256) {
        return _readBalanceInfo(addr);
    }
}

contract PeepsTest is Test {
    Peeps peeps;
    WETH weth;
    IUniswapV2Factory v2Factory;
    IUniswapV2Router02 v2Router;
    IUniswapV2Pair v2Pair;
    LockMock lockMock;

    uint256 private constant ETH_LIQUIDITY = 1 ether;
    address private constant REVENUE_WALLET = address(0xbabe);
    uint96 private constant TOTAL_SUPPLY = type(uint96).max;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function setUp() public {
        lockMock = new LockMock();

        weth = new WETH();

        (v2Factory, v2Router) = _deployUniswap(address(weth));

        peeps = new Peeps(REVENUE_WALLET, address(weth), v2Factory, address(lockMock), TOTAL_SUPPLY);

        peeps.approve(address(v2Router), TOTAL_SUPPLY);

        vm.deal(address(this), ETH_LIQUIDITY);

        v2Pair = IUniswapV2Pair(v2Factory.getPair(address(peeps), address(weth)));
    }

    function testBalancePacking(address addr, uint88 bought, uint80 paid, uint88 amount) public {
        PeepsInternal peepsInternal =
            new PeepsInternal(REVENUE_WALLET, address(weth), v2Factory, address(lockMock), TOTAL_SUPPLY);

        peepsInternal.updateBalanceInfo(addr, bought, paid, amount);

        (uint256 actualBought, uint256 actualPaid, uint256 actualAmount) = peepsInternal.readBalanceInfo(addr);

        assertEq(actualBought, bought);
        assertEq(actualPaid, paid);
        assertEq(actualAmount, amount);
    }

    function testDeploy() public {
        assertEq(peeps.totalSupply(), TOTAL_SUPPLY);
        assertEq(peeps.balanceOf(address(this)), 0);
        assertEq(peeps.balanceOf(address(peeps)), 0);
        assertEq(peeps.balanceOf(address(v2Pair)), 0);
    }

    function testAddLiqudity() public {
        vm.expectEmit(true, true, false, true, address(peeps));
        emit Transfer(address(0), address(v2Pair), TOTAL_SUPPLY);
        vm.expectEmit(true, true, false, true, address(weth));
        emit Transfer(address(0), address(peeps), ETH_LIQUIDITY);
        vm.expectEmit(true, true, false, true, address(weth));
        emit Transfer(address(peeps), address(v2Pair), ETH_LIQUIDITY);

        peeps.addLiquidity{value: 1 ether}();

        assertEq(peeps.balanceOf(address(v2Pair)), TOTAL_SUPPLY);

        (uint256 reserve0, uint256 reserve1,) = v2Pair.getReserves();
        (uint256 reserveToken, uint256 reserveWETH) =
            address(peeps) < address(weth) ? (reserve0, reserve1) : (reserve1, reserve0);

        assertEq(reserveToken, TOTAL_SUPPLY);
        assertEq(reserveWETH, ETH_LIQUIDITY);
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
}
