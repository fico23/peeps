// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract Lock {
    using FixedPointMathLib for uint256;

    uint256 internal constant LOCK_DURATION = 420 hours;
    uint256 internal constant RAISE_GOAL = 420 ether;
    address internal immutable TOKEN;

    uint256 internal constant ETH_PER_TOKEN_OFFSET = 96;
    uint256 internal constant ENDS_OFFSET = 224;
    uint256 internal constant AMOUNT_OFFSET = 128;

    uint256 internal constant MASK_96 = 0xffffffffffffffffffffffff;
    uint256 internal constant MASK_128 = 0xffffffffffffffffffffffffffffffff;

    // Bits Layout:
    // - [0..159]    `ethPerToken`
    // - [160..255]  `tokenLocked`
    // - [184..255]  `totalOnus`
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

    constructor(address token) {
        TOKEN = token;
    }

    function recieve() external payable {
        (uint256 ethPerToken, uint256 tokenLocked) = _readPoolInfo();

        ethPerToken += msg.value.divWad(tokenLocked);

        _writePoolInfo(ethPerToken, tokenLocked);
    }

    function lock(uint256 amount, address recipient) external {
        SafeTransferLib.safeTransferFrom(TOKEN, msg.sender, address(this), amount);

        (uint256 ethPerToken, uint256 tokenLocked) = _readPoolInfo();
        (uint256 ends, uint256 lockedAmount, uint256 debt) = _readUserInfo(msg.sender);

        uint256 newDebt = ethPerToken.mulWad(lockedAmount);
        unchecked {
            if (newDebt != debt) {
                SafeTransferLib.safeTransferETH(msg.sender, newDebt - debt);
            }

            _writePoolInfo(ethPerToken, tokenLocked + amount);
            _writeUserInfo(msg.sender, 0, lockedAmount + amount, newDebt);
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

        (uint256 ethPerToken, uint256 tokenLocked) = _readPoolInfo();

        uint256 newDebt = ethPerToken.mulWad(lockedAmount);

        _clearUserInfo(msg.sender);

        unchecked {
            if (newDebt != debt) {
                SafeTransferLib.safeTransferETH(msg.sender, newDebt - debt);
            }

            _writePoolInfo(ethPerToken, tokenLocked - lockedAmount);
        }

        SafeTransferLib.safeTransfer(TOKEN, msg.sender, lockedAmount);

        emit Unlocked(msg.sender, lockedAmount);
    }

    function claim() external {
        (uint256 ends, uint256 lockedAmount, uint256 debt) = _readUserInfo(msg.sender);
        (uint256 ethPerToken,) = _readPoolInfo();

        uint256 newDebt = ethPerToken.mulWad(lockedAmount);

        if (newDebt == debt) return;

        _writeUserInfo(msg.sender, ends, lockedAmount, newDebt);

        unchecked {
            SafeTransferLib.safeTransferETH(msg.sender, newDebt - debt);
        }
    }

    function _readPoolInfo() internal view returns (uint256, uint256) {
        uint256 currPoolInfo = poolInfo;

        return (currPoolInfo >> ETH_PER_TOKEN_OFFSET, currPoolInfo & MASK_96);
    }

    function _writePoolInfo(uint256 ethPerToken, uint256 tokenLocked) internal {
        poolInfo = tokenLocked & MASK_96 | ethPerToken << ETH_PER_TOKEN_OFFSET;
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
        return poolInfo & MASK_96;
    }
}
