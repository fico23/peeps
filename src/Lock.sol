// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract Lock {
    using FixedPointMathLib for uint256;

    uint256 internal constant LOCK_DURATION = 420 hours;
    address internal constant RAISE_GOAL = 420 ether;
    address internal immutable TOKEN;

    uint256 internal constant ETH_PER_TOKEN_OFFSET = 96;
    uint256 internal constant ENDS_OFFSET = 224;
    uint256 internal constant AMOUNT_OFFSET = 128;

    uint256 internal constant MASK_96 = 0xffffffffffffffffffffffff;
    uint256 internal constant MASK_128 = 0xffffffffffffffffffffffffffffffff;

    // Bits Layout:
    // - [0..159]    `ethPerToken`
    // - [160..255]  `tokenLocked`
    uint256 internal poolInfo;

    struct UserInfo {
        uint32 ends;
        uint96 amount;
        uint128 ethDebt;
    }

    // Bits Layout:
    // - [0..31]    `ends`
    // - [32..127]  `amount`
    // - [128..255]  `ethDebt`
    mapping(address user => uint256 info) private userInfo;

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
            uint256 claimable = newDebt - debt;
            if (claimable > 0) {
                SafeTransferLib.safeTransferETH(msg.sender, claimable);
            }

            _writePoolInfo(ethPerToken, tokenLocked + amount);
            _writeUserInfo(msg.sender, 0, lockedAmount + amount, newDebt);
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
}
