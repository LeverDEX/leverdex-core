// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./RoleAware.sol";
import "./Fund.sol";

/// @title Manage distribution of liquidity stake incentives
/// Some efforts have been made to reduce gas cost at claim time
/// and shift gas burden onto those who would want to withdraw
contract IncentiveDistribution is RoleAware {
    mapping(address => uint256) public rewardAmount;
    address immutable MFI;

    constructor(address _MFI, address _roles) RoleAware(_roles) {
        MFI = _MFI;
    }

    /// Input rewards
    function inputRewards(
        address[] calldata claimants,
        uint256[] calldata rewards
    ) external onlyOwnerExecDisabler {
        for (uint256 i; claimants.length > i; i++) {
            rewardAmount[claimants[i]] += rewards[i];
        }
    }

    /// Withdraw current reward amount
    function withdrawReward() external returns (uint256 withdrawAmount) {
        withdrawAmount = rewardAmount[msg.sender];
        delete rewardAmount[msg.sender];

        Fund(fund()).withdraw(MFI, msg.sender, withdrawAmount);
    }
}
