// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IDeployer} from "./interfaces/IDeployer.sol";
import {console2} from "forge-std/Test.sol";

contract Lock {
    using FixedPointMathLib for uint256;

    uint256 internal constant LOCK_DURATION = 420 hours;
    uint256 internal constant RAISE_GOAL = 420 ether;

    uint256 internal constant ETH_PER_TOKEN_OFFSET = 155;
    uint256 internal constant TOKEN_LOCKED_OFFSET = 69;
    uint256 internal constant ENDS_OFFSET = 224;
    uint256 internal constant AMOUNT_OFFSET = 128;

    uint256 internal constant MASK_69 = 2 ** 69 - 1;
    uint256 internal constant MASK_86 = 2 ** 86 - 1;
    uint256 internal constant MASK_101 = 2 ** 101 - 1;
    uint256 internal constant MASK_96 = 0xffffffffffffffffffffffff;
    uint256 internal constant MASK_128 = 0xffffffffffffffffffffffffffffffff;

    address internal immutable TOKEN;
    address internal immutable UNI_V2_PAIR;
    address internal immutable WETH;
    bool internal immutable IS_TOKEN_FIRST;

    // Bits Layout:
    // - [0..100]    `ethPerToken` - 101 bits
    // - [101..186]  `tokenLocked` - 86 bits
    // - [187..255]  `totalOnus`   - 69 bits
    uint256 internal poolInfo;

    // Bits Layout:
    // - [0..31]    `ends`
    // - [32..127]  `amount`
    // - [128..255]  `ethDebt`
    mapping(address user => uint256 info) internal userInfo;

    event Locked(address addr, uint256 amount);
    event Unlocked(address addr, uint256 amount);

    error UnlockAlreadyStarted();
    error NoLock();
    error UnlockNotStarted();
    error UnlockNotEnded();
    error Unauthorized();

    constructor() {
        (address peeps,, address weth,, address uniV2Pair) = IDeployer(msg.sender).getImmutables();
        TOKEN = peeps;
        UNI_V2_PAIR = uniV2Pair;
        WETH = weth;
        IS_TOKEN_FIRST = peeps < weth;
    }

    function lock(uint256 amount) external {
        SafeTransferLib.safeTransferFrom(TOKEN, msg.sender, address(this), amount);

        (uint256 ethPerToken, uint256 tokenLocked, uint256 totalOnus) = _readPoolInfo();
        (, uint256 lockedAmount, uint256 debt) = _readUserInfo(msg.sender);

        uint256 newDebt = ethPerToken.mulWad(lockedAmount);
        unchecked {
            _writePoolInfo(ethPerToken, tokenLocked + amount, totalOnus);
            _writeUserInfo(msg.sender, 0, lockedAmount + amount, newDebt);

            if (newDebt != debt) {
                SafeTransferLib.safeTransferETH(msg.sender, newDebt - debt);
            }
        }

        emit Locked(msg.sender, amount);
    }

    function startUnlock() external {
        (uint256 ends, uint256 lockedAmount, uint256 debt) = _readUserInfo(msg.sender);

        if (ends != 0) revert UnlockAlreadyStarted();
        if (lockedAmount == 0) revert NoLock();

        ends = block.timestamp + LOCK_DURATION;

        _writeUserInfo(msg.sender, ends, lockedAmount, debt);
    }

    function unlock() external {
        (uint256 ends, uint256 lockedAmount, uint256 debt) = _readUserInfo(msg.sender);

        if (ends == 0) revert UnlockNotStarted();
        if (ends > block.timestamp) revert UnlockNotEnded();

        (uint256 ethPerToken, uint256 tokenLocked, uint256 totalOnus) = _readPoolInfo();

        uint256 newDebt = ethPerToken.mulWad(lockedAmount);

        _clearUserInfo(msg.sender);

        unchecked {
            if (newDebt != debt) {
                SafeTransferLib.safeTransferETH(msg.sender, newDebt - debt);
            }

            _writePoolInfo(ethPerToken, tokenLocked - lockedAmount, totalOnus);
        }

        SafeTransferLib.safeTransfer(TOKEN, msg.sender, lockedAmount);

        emit Unlocked(msg.sender, lockedAmount);
    }

    function claim() external {
        (uint256 ends, uint256 lockedAmount, uint256 debt) = _readUserInfo(msg.sender);
        (uint256 ethPerToken,,) = _readPoolInfo();

        uint256 newDebt = ethPerToken.mulWad(lockedAmount);

        if (newDebt == debt) return;

        _writeUserInfo(msg.sender, ends, lockedAmount, newDebt);

        unchecked {
            SafeTransferLib.safeTransferETH(msg.sender, newDebt - debt);
        }
    }

    function _readPoolInfo() internal view returns (uint256, uint256, uint256) {
        uint256 currPoolInfo = poolInfo;

        return (
            currPoolInfo >> ETH_PER_TOKEN_OFFSET, currPoolInfo >> TOKEN_LOCKED_OFFSET & MASK_86, currPoolInfo & MASK_69
        );
    }

    function _writePoolInfo(uint256 ethPerToken, uint256 tokenLocked, uint256 totalOnus) internal {
        poolInfo = totalOnus | tokenLocked << TOKEN_LOCKED_OFFSET | ethPerToken << ETH_PER_TOKEN_OFFSET;
    }

    function _readUserInfo(address user) internal view returns (uint256, uint256, uint256) {
        uint256 currUserInfo = userInfo[user];

        return (currUserInfo >> ENDS_OFFSET, currUserInfo >> AMOUNT_OFFSET & MASK_96, currUserInfo & MASK_128);
    }

    function _writeUserInfo(address user, uint256 ends, uint256 amount, uint256 ethDebt) internal {
        userInfo[user] = ends << ENDS_OFFSET | amount << AMOUNT_OFFSET | ethDebt;
    }

    function _clearUserInfo(address user) internal {
        delete userInfo[user];
    }

    function getTotalOnus() external view returns (uint256) {
        return poolInfo & MASK_69;
    }

    function notifyAmount(uint256 amount) external {
        if (msg.sender != TOKEN) revert Unauthorized();

        (uint256 ethPerToken, uint256 tokenLocked, uint256 totalOnus) = _readPoolInfo();

        // console2.log('ethPerToken %s tokenLocked ')

        unchecked {
            ethPerToken += amount.divWad(tokenLocked);
            totalOnus += amount;
        }

        _writePoolInfo(ethPerToken, tokenLocked, totalOnus);
    }
}
