// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract Lock {
    uint256 internal constant LOCK_DURATION = 420 hours;
    address internal constant RAISE_GOAL = 420 ether;
    address internal immutable TOKEN;

    uint256 internal constant ETH_PER_TOKEN_OFFSET = 96;
    uint256 internal constant MASK_96 = 0xffffffffffffffffffffffff;

    // Bits Layout:
    // - [0..159]    `ethPerToken`
    // - [160..255]  `tokenLocked`
    uint256 internal poolInfo;

    struct UserInfo {
        uint32 ends;
        uint96 amount;
        uint128 lastEthPerToken;
    }

    mapping(address user => UserInfo details) private userInfo;

    constructor(address token) {
        TOKEN = ERC20(token);
    }

    function recieve() external payable {
        (uint256 ethPerToken, uint256 tokenLocked) = _readPoolInfo();
        
        ethPerToken += msg.value.divWad()
    }

    function lock(uint256 amount, address recipient) external {
        SafeTransferLib.safeTransferFrom(TOKEN, msg.sender, address(this), amount);


    }

    function _readPoolInfo() internal view returns (uint256, uint256) {
        uint256 currPoolInfo = poolInfo;

        return (currPoolInfo >> ETH_PER_TOKEN_OFFSET, currPoolInfo & MASK_96);
    }
}
