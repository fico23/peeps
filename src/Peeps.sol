// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.22;

import {IWETH} from "v2-periphery/interfaces/IWETH.sol";
import {ILock} from "./interfaces/ILock.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @notice Worlds best tax token
/// @author fico23
contract Peeps {
    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/
    uint256 public immutable totalSupply;

    // Bits Layout:
    // - [0..159]    `paid`
    // - [160..255] `amount`
    mapping(address => uint256) internal _balanceOf;

    mapping(address => mapping(address => uint256)) public allowance;

    // /*//////////////////////////////////////////////////////////////
    //                         CONSTANTS & IMMUTABLES
    // //////////////////////////////////////////////////////////////*/
    IUniswapV2Pair internal immutable UNI_V2_PAIR;
    bool internal immutable IS_TOKEN_FIRST;
    address internal immutable REVENUE_WALLET;
    IWETH internal immutable WETH;
    ILock internal immutable LOCK;
    address internal immutable DEPLOYER;

    uint256 internal constant HUNDRED_PERCENT = 100;
    uint256 internal constant PAID_OFFSET = 96;
    uint256 internal constant MASK_160 = type(uint160).max;
    uint256 internal constant MASK_96 = type(uint96).max;
    uint256 internal constant WAD = 1e18;

    uint256 internal constant K = 420e28;
    uint256 internal constant X0 = 69e17;
    uint256 internal constant ONUS_CAP = 420 ether;
    uint256 internal constant ONUS_PRECISION = 1e12;

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(address => uint256) public nonces;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    // /*//////////////////////////////////////////////////////////////
    //                         ERRORS
    // //////////////////////////////////////////////////////////////*/
    error InsufficientInputAmount();
    error InsufficientOutputAmount();
    error InsufficientLiquidity();
    error Unauthorized();
    error LiquidityAlreadyAdded();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _revenueWallet, address _weth, IUniswapV2Factory _factory, address lock, uint96 _totalSupply) {
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

        REVENUE_WALLET = _revenueWallet;

        WETH = IWETH(_weth);
        IS_TOKEN_FIRST = address(this) < _weth;

        LOCK = ILock(lock);

        totalSupply = _totalSupply;

        UNI_V2_PAIR = IUniswapV2Pair(_factory.createPair(address(this), _weth));

        DEPLOYER = msg.sender;
    }

    function addLiquidity() external payable {
        if (msg.sender != DEPLOYER) revert Unauthorized();
        if (_balanceOf[address(UNI_V2_PAIR)] != 0) revert LiquidityAlreadyAdded();

        _balanceOf[address(UNI_V2_PAIR)] = totalSupply;
        emit Transfer(address(0), address(UNI_V2_PAIR), totalSupply);

        WETH.deposit{value: msg.value}();
        assert(IWETH(WETH).transfer(address(UNI_V2_PAIR), msg.value));

        UNI_V2_PAIR.mint(DEPLOYER);
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        _transfer(from, to, amount);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                             EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PEEPS"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    function readBalanceInfo(address addr) external view returns (uint256, uint256) {
        return _readBalanceInfo(addr);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _readBalanceInfo(address addr) internal view returns (uint256 paid, uint256 amount) {
        uint256 balanceInfo = _balanceOf[addr];

        paid = balanceInfo >> PAID_OFFSET & MASK_160;
        amount = balanceInfo & MASK_96;
    }

    function _updateBalanceInfo(address addr, uint256 paid, uint256 amount) internal {
        // cleanup ends, paid, bought
        _balanceOf[addr] = amount | paid << PAID_OFFSET;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        (uint256 fromPaid, uint256 fromAmount) = _readBalanceInfo(from);
        (uint256 toPaid, uint256 toAmount) = _readBalanceInfo(to);

        uint256 fromBought = fromAmount;

        fromAmount -= amount;
        unchecked {
            if (to == address(UNI_V2_PAIR)) {
                // selling -> calculate potential sellers onus
                (uint256 reserveToken, uint256 reserveWETH) = _getReserves();

                uint256 canSellFor = _getAmountOut(fromBought, reserveToken, reserveWETH) * WAD;

                _updateBalanceInfo(from, fromPaid - fromPaid * amount / fromBought, fromAmount);

                if (canSellFor > fromPaid) {
                    uint256 onus = _getOnus(LOCK.getTotalOnus(), amount);
                    if (onus != 0) {
                        _executeSwap(from, onus, reserveToken, reserveWETH);
                        amount -= onus;
                    }
                }
                _balanceOf[address(UNI_V2_PAIR)] += amount;
            } else if (from == address(UNI_V2_PAIR)) {
                // buying -> update buyers onus details
                (uint256 reserveToken, uint256 reserveWETH) = _getReserves();

                toPaid += _getAmountIn(amount, reserveWETH, reserveToken) * WAD;
                _balanceOf[address(UNI_V2_PAIR)] = fromAmount;
                _updateBalanceInfo(to, toPaid, toAmount + amount);
            } else {
                // pleb transfer -> transfer their onus details
                uint256 wouldPay = fromPaid * amount / fromBought;

                _updateBalanceInfo(from, fromPaid - wouldPay, fromAmount);
                _updateBalanceInfo(to, toPaid + wouldPay, toAmount + amount);
            }
        }

        emit Transfer(from, to, amount);
    }

    function _executeSwap(address from, uint256 amountIn, uint256 reserveToken, uint256 reserveWETH) internal {
        uint256 amountOut = _getAmountOut(amountIn, reserveToken, reserveWETH);

        emit Transfer(from, address(this), amountIn);

        unchecked {
            _balanceOf[address(UNI_V2_PAIR)] += amountIn;
        }
        emit Transfer(address(this), address(UNI_V2_PAIR), amountIn);

        (uint256 amount0Out, uint256 amount1Out) = IS_TOKEN_FIRST ? (uint256(0), amountOut) : (amountOut, uint256(0));
        UNI_V2_PAIR.swap(amount0Out, amount1Out, address(LOCK), new bytes(0));
    }

    function _getReserves() internal view returns (uint256 reserveA, uint256 reserveB) {
        (uint256 reserve0, uint256 reserve1,) = UNI_V2_PAIR.getReserves();
        (reserveA, reserveB) = IS_TOKEN_FIRST ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InsufficientInputAmount();
        if (reserveIn == 0) revert InsufficientLiquidity();
        if (reserveOut == 0) revert InsufficientLiquidity();
        unchecked {
            uint256 amountInWithFee = amountIn * 997;
            uint256 numerator = amountInWithFee * reserveOut;
            uint256 denominator = reserveIn * 1000 + amountInWithFee;
            amountOut = numerator / denominator;
        }
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        if (amountOut == 0) revert InsufficientOutputAmount();
        if (reserveIn == 0) revert InsufficientLiquidity();
        if (reserveOut == 0) revert InsufficientLiquidity();
        unchecked {
            uint256 numerator = reserveIn * amountOut * 1000;
            uint256 denominator = (reserveOut - amountOut) * 997;
            amountIn = numerator / denominator + 1;
        }
    }

    // f(x) = 420/(x + 6.9)
    // f(0) ≈ 61%
    // f(420 ether - 1) ≈ 1%
    function _getOnus(uint256 totalOnus, uint256 onusableAmount) internal pure returns (uint256) {
        if (totalOnus > ONUS_CAP) return 0;
        unchecked {
            return K * onusableAmount / (totalOnus + X0) / ONUS_PRECISION;
        }
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL VIEW
    //////////////////////////////////////////////////////////////*/
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function name() public view virtual returns (string memory) {
        return "PEEPS";
    }

    function symbol() public view virtual returns (string memory) {
        return "PEEP";
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function balanceOf(address addr) public view returns (uint256) {
        return uint256(uint96(_balanceOf[addr]));
    }
}
