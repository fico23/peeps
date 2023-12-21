// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {IWETH} from "v2-periphery/interfaces/IWETH.sol";
import {IRevenueWallet} from "./interfaces/IRevenueWallet.sol";

/// @notice Peep
/// @author fico23
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
contract Peeps {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    uint8 public immutable decimals;

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;

    // Bits Layout:
    // - [0..31]    `ends`
    // - [32..95]   `bought`
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
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    uint256 internal constant ENDS_OFFSET = 224;
    uint256 internal constant BOUGHT_OFFSET = 160;
    uint256 internal constant PAID_OFFSET = 96;
    uint256 internal constant MASK_32 = 0xffffffff;
    uint256 internal constant MASK_64 = 0xffffffffffffffff;
    uint256 internal constant MASK_96 = 0xffffffffffffffffffffffff;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _revenueWallet, address _weth, IUniswapV2Factory _factory, uint256 _totalSupply) {
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

        REVENUE_WALLET = _revenueWallet;

        WETH = IWETH(_weth);
        IS_TOKEN_FIRST = address(this) < _weth;

        totalSupply = _totalSupply;

        address pair = _factory.createPair(address(this), _weth);
        UNI_V2_PAIR = IUniswapV2Pair(pair);

        balanceOf[msg.sender] = _totalSupply;
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
        _balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            _balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        _balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            _balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

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
                keccak256(bytes(name)),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _parseBalanceInfo(address addr)
        internal
        view
        returns (uint256 ends, uint256 paid, uint256 bought, uint256 amount)
    {
        uint256 balanceInfo = _balanceOf[addr];

        ends = balanceInfo >> ENDS_OFFSET;
        paid = balanceInfo >> PAID_OFFSET & MASK_64;
        bought = balanceInfo >> BOUGHT_OFFSET & MASK_64;
        amount = balanceInfo & MASK_96;
    }

    function _updateBalanceInfoEnded(address addr, uint256 newAmount) internal {
        // cleanup ends, paid, bought
        _balanceOf[addr] = newAmount & MASK_96;
    }

    function _calculateProfit(uint256 paid, uint256 bought, uint256 sellingAmount) internal returns (uint256) {
        unchecked {
            uint256 wouldSellFor = bought * sellingAmount / paid;
            (uint256 reserveToken, uint256 reserveWETH) = _getReserves();
            uint256 amountOut = _getAmountOut(sellingAmount, reserveToken, reserveWETH);

            return wouldSellFor > amountOut ? 0 : amountOut - wouldSellFor;
        }
    }

    function _transfer(address from, address to, uint256 amount) internal {
        (uint256 fromEnds, uint256 fromPaid, uint256 fromBought, uint256 fromAmount) = _parseBalanceInfo(from);
        (uint256 toEnds, uint256 toPaid, uint256 toBought, uint256 toAmount) = _parseBalanceInfo(to);

        fromAmount -= amount;

        if (to == UNI_V2_PAIR) {
            if (fromEnds > block.timestamp) {
                _updateBalanceInfoEnded(from, fromAmount);
            } else {
                // tax
                (uint256 reserveToken, uint256 reserveWETH) = _getReserves();

                uint256 taxableAmount = amount < fromBought ? amount : fromBought;
                uint256 wethAmountSold = _getAmountOut(taxableAmount, reserveToken, reserveWETH);

                uint256 wethAmountBought = taxableAmount * fromBought / fromPaid;

                if (wethAmountSold > wethAmountBought) {
                    uint256 tax
                }
            }
        } else if (from == UNI_V2_PAIR) {} else {}
    }

    function _executeSwap(uint256 amountIn) internal {
        (uint256 reserveToken, uint256 reserveWETH) = _getReserves();
        uint256 amountOut = _getAmountOut(amountIn, reserveToken, reserveWETH);

        balanceOf[address(this)] = 0;
        unchecked {
            balanceOf[address(UNI_V2_PAIR)] += amountIn;
        }
        emit Transfer(address(this), address(UNI_V2_PAIR), amountIn);

        (uint256 amount0Out, uint256 amount1Out) = IS_TOKEN_FIRST ? (uint256(0), amountOut) : (amountOut, uint256(0));
        UNI_V2_PAIR.swap(amount0Out, amount1Out, REVENUE_WALLET, new bytes(0));
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
