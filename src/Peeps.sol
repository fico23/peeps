// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.22;

import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IWETH} from "v2-periphery/interfaces/IWETH.sol";
import {ILock} from "./interfaces/ILock.sol";
import {BlazeLibrary} from "./libraries/BlazeLibrary.sol";
import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";

/// @notice Peep
/// @author fico23
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
contract Peeps {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;

    // Bits Layout:
    // - [0..95]    `bought`
    // - [96..159]  `paid`
    // - [160..255] `amount`
    mapping(address => uint256) internal _balanceOf;

    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(address => uint256) public nonces;

    // /*//////////////////////////////////////////////////////////////
    //                         CONSTANTS & IMMUTABLES
    // //////////////////////////////////////////////////////////////*/
    uint256 internal constant HUNDRED_PERCENT = 100;
    IUniswapV2Pair internal immutable UNI_V2_PAIR;
    bool internal immutable IS_TOKEN_FIRST;
    address internal immutable REVENUE_WALLET;
    IWETH internal immutable WETH;
    ILock internal immutable LOCK;

    uint256 internal constant BOUGHT_OFFSET = 160;
    uint256 internal constant PAID_OFFSET = 96;
    uint256 internal constant MASK_64 = 0xffffffffffffffff;
    uint256 internal constant MASK_96 = 0xffffffffffffffffffffffff;

    // /*//////////////////////////////////////////////////////////////
    //                         ERRORS
    // //////////////////////////////////////////////////////////////*/
    error InsufficientInputAmount();
    error InsufficientOutputAmount();
    error InsufficientLiquidity();

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

        address pair = _factory.createPair(address(this), _weth);
        UNI_V2_PAIR = IUniswapV2Pair(pair);

        _balanceOf[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
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

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _parseBalanceInfo(address addr) internal view returns (uint256 bought, uint256 paid, uint256 amount) {
        uint256 balanceInfo = _balanceOf[addr];

        bought = balanceInfo >> BOUGHT_OFFSET;
        paid = balanceInfo >> PAID_OFFSET & MASK_64;
        amount = balanceInfo & MASK_96;
    }

    function _updateBalanceInfoEnded(address addr, uint256 amount) internal {
        // cleanup ends, paid, bought
        _balanceOf[addr] = amount & MASK_96;
    }

    function _updateBalanceInfo(address addr, uint256 bought, uint256 paid, uint256 amount) internal {
        // cleanup ends, paid, bought
        _balanceOf[addr] = amount | paid >> PAID_OFFSET | bought >> BOUGHT_OFFSET;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        (uint256 fromBought, uint256 fromPaid, uint256 fromAmount) = _parseBalanceInfo(from);
        (uint256 toBought, uint256 toPaid, uint256 toAmount) = _parseBalanceInfo(to);

        fromAmount -= amount;
        unchecked {
            if (to == address(UNI_V2_PAIR)) {
                // selling -> calculate potential sellers onus
                (uint256 reserveToken, uint256 reserveWETH) = _getReserves();

                uint256 onusableAmount = amount < fromBought ? amount : fromBought;

                uint256 sellingFor = _getAmountOut(onusableAmount, reserveToken, reserveWETH);
                uint256 boughtWith = onusableAmount * fromBought / fromPaid;

                if (sellingFor > boughtWith) {
                    uint256 onus = BlazeLibrary.getOnus(LOCK.getTotalOnus(), sellingFor - boughtWith);
                    _executeSwap(from, onus, reserveToken, reserveWETH);

                    fromBought -= amount;
                    fromPaid -= sellingFor;

                    amount -= onus;
                }
            } else if (from == address(UNI_V2_PAIR)) {
                // buying -> update buyers onus details
                (uint256 reserveToken, uint256 reserveWETH) = _getReserves();

                toBought += amount;
                toPaid += _getAmountIn(amount, reserveWETH, reserveToken);
            } else {
                // pleb transfer -> transfer their onus details
                fromBought -= amount;
                uint256 wouldPay = amount * fromPaid / fromBought;
                fromPaid -= wouldPay;

                toBought += amount;
                toPaid += wouldPay;
            }

            toAmount += amount;
        }

        _updateBalanceInfo(from, fromBought, fromPaid, fromAmount);
        _updateBalanceInfo(to, toBought, toPaid, toAmount);
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
