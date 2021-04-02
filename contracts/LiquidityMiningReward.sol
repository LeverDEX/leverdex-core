// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IncentiveDistribution.sol";

/// @title Manaage rewards for liquidity mining
contract LiquidityMiningReward is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakeToken;
    mapping(address => uint256) public stakeAmounts;
    IncentiveDistribution internal immutable incentiveDistributor;
    uint256 public immutable incentiveStart;

    constructor(
        address _incentiveDistributor,
        address _stakeToken,
        uint256 startTimestamp
    ) {
        incentiveDistributor = IncentiveDistribution(_incentiveDistributor);
        stakeToken = IERC20(_stakeToken);
        incentiveStart = startTimestamp;
    }

    /// Deposit stake tokens
    function depositStake(uint256 amount) external {
        require(
            block.timestamp > incentiveStart,
            "Incentive hasn't started yet"
        );

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        incentiveDistributor.addToClaimAmount(0, msg.sender, amount);

        stakeAmounts[msg.sender] += amount;
    }

    /// Withdraw stake tokens
    function withdrawStake(uint256 amount) external {
        uint256 stakeAmount = stakeAmounts[msg.sender];
        require(stakeAmount >= amount, "Not enough stake to withdraw");

        stakeAmounts[msg.sender] = stakeAmount - amount;

        incentiveDistributor.subtractFromClaimAmount(0, msg.sender, amount);

        stakeToken.safeTransfer(msg.sender, amount);
    }
}

// USDC - MFI pair token
// 0x9d640080af7c81911d87632a7d09cc4ab6b133ac

// on ropsten:
// 0xc4c79A0e1C7A9c79f1e943E3a5bEc65396a5434a
