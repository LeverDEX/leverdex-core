// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.0;

import "./Fund.sol";
import "./HourlyBondSubscriptionLending.sol";
import "./BondLending.sol";
import "./IncentivizedHolder.sol";

contract Lending is
    BaseLending,
    HourlyBondSubscriptionLending,
    BondLending,
    IncentivizedHolder
{
    /// @dev accumulate interest per token (like compound indices)
    mapping(address => YieldAccumulator) public borrowYieldAccumulators;
    /// @dev IDs for all bonds held by an address
    mapping(address => uint256[]) public bondIds;

    constructor(address _roles) RoleAware(_roles) Ownable() {}

    /// @dev how much interest has accrued to a borrowed balance over time
    function applyBorrowInterest(
        uint256 balance,
        address token,
        uint256 yieldQuotientFP
    ) external returns (uint256) {
        YieldAccumulator storage yA =
            getUpdatedCumulativeYieldFP(
                token,
                borrowYieldAccumulators,
                block.timestamp
            );
        return applyInterest(balance, yA.accumulatorFP, yieldQuotientFP);
    }

    /// @dev view function to get current borrowing interest
    function viewBorrowInterest(
        uint256 balance,
        address token,
        uint256 yieldQuotientFP
    ) external view returns (uint256) {
        uint256 accumulatorFP =
            viewCumulativeYieldFP(
                token,
                borrowYieldAccumulators,
                block.timestamp
            );
        return applyInterest(balance, accumulatorFP, yieldQuotientFP);
    }

    /// @dev gets called by router to register if a trader borrows tokens
    function registerBorrow(address token, uint256 amount) external {
        require(isBorrower(msg.sender), "Not an approved borrower");
        require(Fund(fund()).activeTokens(token), "Not an approved token");
        totalBorrowed[token] += amount;
        require(
            totalLending[token] >= totalBorrowed[token],
            "Insufficient capital to lend, try again later!"
        );
    }

    /// @dev gets called by router if loan is extinguished
    function payOff(address token, uint256 amount) external {
        require(isBorrower(msg.sender), "Not an approved borrower");
        totalBorrowed[token] -= amount;
    }

    /// @dev get the borrow yield
    function viewBorrowingYieldFP(address token)
        external
        view
        returns (uint256)
    {
        return
            viewCumulativeYieldFP(
                token,
                borrowYieldAccumulators,
                block.timestamp
            );
    }

    /// @dev In a liquidity crunch make a fallback bond until liquidity is good again
    function _makeFallbackBond(
        address token,
        address holder,
        uint256 amount
    ) internal override {
        _makeHourlyBond(token, holder, amount);
    }

    /// @dev withdraw an hour bond
    function withdrawHourlyBond(address token, uint256 amount) external {
        HourlyBond storage bond = hourlyBondAccounts[token][msg.sender];
        // apply all interest
        updateHourlyBondAmount(token, bond);
        super._withdrawHourlyBond(token, bond, msg.sender, amount);

        withdrawClaim(msg.sender, token, amount);
    }

    /// @dev buy hourly bond subscription
    function buyHourlyBondSubscription(address token, uint256 amount) external {
        if (lendingTarget(token) >= totalLending[token] + amount) {
            require(
                Fund(fund()).depositFor(msg.sender, token, amount),
                "Could not transfer bond deposit token to fund"
            );
            super._makeHourlyBond(token, msg.sender, amount);

            stakeClaim(msg.sender, token, amount);
        }
    }

    /// @dev buy fixed term bond that does not renew
    function buyBond(
        address token,
        uint256 runtime,
        uint256 amount,
        uint256 minReturn
    ) external returns (uint256 bondIndex) {
        if (
            lendingTarget(token) >= totalLending[token] + amount &&
            maxRuntime >= runtime &&
            runtime >= minRuntime
        ) {
            bondIndex = super._makeBond(
                msg.sender,
                token,
                runtime,
                amount,
                minReturn
            );
            bondIds[msg.sender].push(bondIndex);

            stakeClaim(msg.sender, token, amount);
        }
    }

    /// @dev send back funds of bond after maturity
    function withdrawBond(uint256 bondId) external {
        Bond storage bond = bonds[bondId];
        require(msg.sender == bond.holder, "Not holder of bond");
        require(
            block.timestamp > bond.maturityTimestamp,
            "bond is still immature"
        );

        super._withdrawBond(bond);
        // in case of a shortfall, governance can step in to provide
        // additonal compensation beyond the usual incentive which
        // gets withdrawn here
        withdrawClaim(msg.sender, bond.token, bond.originalPrice);
    }
}
