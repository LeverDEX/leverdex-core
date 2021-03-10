// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.0;

import "./RoleAware.sol";
import "./IncentiveDistribution.sol";
import "./Fund.sol";
import "./CrossMarginTrading.sol";
import "./MarginRouter.sol";

contract TokenAdmin is RoleAware, Ownable {
    uint256 public totalLendingTargetPortion;
    uint256 public totalBorrowingTargetPortion;
    address[] public incentiveTokens;
    mapping(address => uint256) public tokenWeights;
    uint256 public totalTokenWeights;
    mapping(address => uint8) public tokenLendingTranches;
    mapping(address => uint8) public tokenBorrowingTranches;
    uint8 public nextTrancheIndex = 20;

    // TODO give this contract ownership of incentive distribution
    // after everything else is incentivized
    constructor(
        uint256 lendingTargetPortion,
        uint256 borrowingTargetPortion,
        address _roles
    ) RoleAware(_roles) Ownable() {
        totalLendingTargetPortion = lendingTargetPortion;
        totalBorrowingTargetPortion = borrowingTargetPortion;
    }

    function activateToken(
        address token,
        uint256 exposureCap,
        uint256 incentiveWeight
    ) external onlyOwner {
        require(!Fund(fund()).activeTokens(token), "Token already is active");

        Fund(fund()).activateToken(token);
        CrossMarginTrading(marginTrading()).setTokenCap(token, exposureCap);
        // TODO lending cap as well

        if (incentiveWeight > 0) {
            totalTokenWeights += incentiveWeight;
            tokenWeights[token] = incentiveWeight;
            IncentiveDistribution iD =
                IncentiveDistribution(incentiveDistributor());

            // init lending
            uint256 lendingShare =
                calcTrancheShare(incentiveWeight, totalLendingTargetPortion);
            iD.initTranche(nextTrancheIndex, lendingShare);
            tokenLendingTranches[token] = nextTrancheIndex;
            Lending(lending()).setIncentiveTranche(token, nextTrancheIndex);
            nextTrancheIndex++;

            // init borrowing
            uint256 borrowingShare =
                calcTrancheShare(incentiveWeight, totalBorrowingTargetPortion);
            iD.initTranche(nextTrancheIndex, borrowingShare);
            tokenBorrowingTranches[token] = nextTrancheIndex;
            MarginRouter(router()).setIncentiveTranche(token, nextTrancheIndex);
            nextTrancheIndex++;

            updateIncentiveShares(iD);
            incentiveTokens.push(token);
        }
    }

    function changeTokenCap(address token, uint256 exposureCap)
        external
        onlyOwner
    {
        // TODO add token cap to lending as well
        CrossMarginTrading(marginTrading()).setTokenCap(token, exposureCap);
    }

    function changeTokenIncentiveWeight(address token, uint256 tokenWeight)
        external
        onlyOwner
    {
        totalTokenWeights =
            totalTokenWeights +
            tokenWeight -
            tokenWeights[token];
        tokenWeights[token] = tokenWeight;

        updateIncentiveShares(IncentiveDistribution(incentiveDistributor()));
    }

    function updateIncentiveShares(IncentiveDistribution iD) internal {
        for (uint8 i = 0; incentiveTokens.length > i; i++) {
            address incentiveToken = incentiveTokens[i];
            uint256 tokenWeight = tokenWeights[incentiveToken];
            uint256 lendingShare =
                calcTrancheShare(tokenWeight, totalLendingTargetPortion);
            iD.setTrancheShare(
                tokenLendingTranches[incentiveToken],
                lendingShare
            );

            uint256 borrowingShare =
                calcTrancheShare(tokenWeight, totalBorrowingTargetPortion);
            iD.setTrancheShare(
                tokenBorrowingTranches[incentiveToken],
                borrowingShare
            );
        }
    }

    function calcTrancheShare(uint256 incentiveWeight, uint256 targetPortion)
        internal
        view
        returns (uint256)
    {
        return (incentiveWeight * targetPortion) / totalTokenWeights;
    }

    function setLendingTargetPortion(uint256 portion) external onlyOwner {
        totalLendingTargetPortion = portion;
    }

    function setBorrowingTargetPortion(uint256 portion) external onlyOwner {
        totalBorrowingTargetPortion = portion;
    }

    function relinquishOwnershipOfDistributor(address newOwner)
        external
        onlyOwner
    {
        IncentiveDistribution(incentiveDistributor()).transferOwnership(
            newOwner
        );
    }
}