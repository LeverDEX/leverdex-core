// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "./BaseLending.sol";
import "./Fund.sol";

struct Bond {
    address holder;
    address token;
    uint256 originalPrice;
    uint256 returnAmount;
    uint256 maturityTimestamp;
    uint256 runtime;
    uint256 yieldFP;
}

/** 
@title Lending for fixed runtime, fixed interest
Lenders can pick their own bond maturity date
@dev In order to manage interest rates for the different
maturities and create a yield curve we bucket
bond runtimes into weighted baskets and adjust
rates individually per bucket, based on supply and demand.
*/
abstract contract BondLending is BaseLending {
    uint256 public minRuntime = 30 days;
    uint256 public maxRuntime = 365 days;
    uint256 public diffMaxMinRuntime;
    /** 
    @dev this is the numerator under runtimeWeights.
    any excess left over is the weight of hourly bonds
    */
    uint256 public constant WEIGHT_TOTAL_10k = 10_000;
    uint256 public borrowingMarkupFP;

    struct BondBucketMetadata {
        uint256 runtimeWeight;
        uint256 buyingSpeed;
        uint256 lastBought;
        uint256 withdrawingSpeed;
        uint256 lastWithdrawn;
        uint256 yieldLastUpdated;

        uint256 totalLending;
        uint256 runtimeYieldFP;
    }

    mapping(uint256 => Bond) public bonds;

    mapping(address => BondBucketMetadata[]) public bondBucketMetadata;

    uint256 public nextBondIndex = 1;

    event LiquidityWarning(
        address indexed token,
        address indexed holder,
        uint256 value
    );

    function _makeBond(
        address holder,
        address token,
        uint256 runtime,
        uint256 amount,
        uint256 minReturn
    ) internal returns (uint256 bondIndex) {
        uint256 bucketIndex = getBucketIndex(token, runtime);
        BondBucketMetadata storage bondMeta = bondBucketMetadata[token][bucketIndex];

        uint256 yieldFP =
            calcBondYieldFP(
                token,
                amount,
                runtime,
                bondMeta
            );

        uint256 bondReturn = (yieldFP * amount) / FP32;
        if (bondReturn >= minReturn) {
            Fund(fund()).depositFor(holder, token, amount);
            uint256 interpolatedAmount = (amount + bondReturn) / 2;
            lendingMeta[token].totalLending += interpolatedAmount;

            bondMeta.totalLending += interpolatedAmount;

            bondIndex = nextBondIndex;
            nextBondIndex++;

            bonds[bondIndex] = Bond({
                holder: holder,
                token: token,
                originalPrice: amount,
                returnAmount: bondReturn,
                maturityTimestamp: block.timestamp + runtime,
                runtime: runtime,
                yieldFP: yieldFP
            });

            (bondMeta.buyingSpeed, bondMeta.lastBought) =
                updateSpeed(
                bondMeta.buyingSpeed,
                bondMeta.lastBought,
                amount,
                runtime
            );
        }
    }

    function _withdrawBond(uint256 bondId, Bond storage bond) internal {
        address token = bond.token;
        uint256 bucketIndex = getBucketIndex(token, bond.runtime);
        BondBucketMetadata storage bondMeta = bondBucketMetadata[token][bucketIndex];

        uint256 returnAmount = bond.returnAmount;
        address holder = bond.holder;

        uint256 interpolatedAmount = (bond.originalPrice + returnAmount) / 2;

        LendingMetadata storage meta = lendingMeta[token];
        meta.totalLending -= interpolatedAmount;
        bondMeta.totalLending -= interpolatedAmount;

        (bondMeta.withdrawingSpeed, bondMeta.lastWithdrawn) =
            updateSpeed(
                    bondMeta.withdrawingSpeed,
            bondMeta.lastWithdrawn,
            bond.originalPrice,
            bond.runtime
        );

        delete bonds[bondId];
        if (
            meta.totalBorrowed > meta.totalLending ||
            IERC20(token).balanceOf(fund()) < returnAmount
        ) {
            // apparently there is a liquidity issue
            emit LiquidityWarning(token, holder, returnAmount);
            _makeFallbackBond(token, holder, returnAmount);
        } else {
            Fund(fund()).withdraw(token, holder, returnAmount);
        }
    }

    function calcBondYieldFP(
        address token,
        uint256 addedAmount,
        uint256 runtime,
        BondBucketMetadata storage bucketMeta
    ) internal view returns (uint256 yieldFP) {
        uint256 totalLendingInBucket = addedAmount + bucketMeta.totalLending;

        yieldFP = bucketMeta.runtimeYieldFP;
        uint256 lastUpdated = bucketMeta.yieldLastUpdated;

        LendingMetadata storage meta = lendingMeta[token];
        uint256 bucketTarget =
            (lendingTarget(meta) * bucketMeta.runtimeWeight) /
                WEIGHT_TOTAL_10k;

        uint256 buying = bucketMeta.buyingSpeed;
        uint256 withdrawing = bucketMeta.withdrawingSpeed;

        YieldAccumulator storage borrowAccumulator =
            borrowYieldAccumulators[token];

        uint256 yieldGeneratedFP =
            borrowAccumulator.hourlyYieldFP * meta.totalBorrowed / (1 + meta.totalLending);
        uint256 _maxHourlyYieldFP = min(maxHourlyYieldFP, yieldGeneratedFP);

        uint256 bucketMaxYield = _maxHourlyYieldFP * (runtime / (1 hours));

        yieldFP = updatedYieldFP(
            yieldFP,
            lastUpdated,
            totalLendingInBucket,
            bucketTarget,
            buying,
            withdrawing,
            bucketMaxYield
        );
    }

    /// Get view of returns on bond
    function viewBondReturn(
        address token,
        uint256 runtime,
        uint256 amount
    ) external view returns (uint256) {
        uint256 bucketIndex = getBucketIndex(token, runtime);
        uint256 yieldFP =
            calcBondYieldFP(
                token,
                amount + bondBucketMetadata[token][bucketIndex].totalLending,
                runtime,
                bondBucketMetadata[token][bucketIndex]
            );
        return (yieldFP * amount) / FP32;
    }

    function getBucketIndex(address token, uint256 runtime)
        internal
        view
        returns (uint256 bucketIndex)
    {
        uint256 bucketSize = diffMaxMinRuntime / bondBucketMetadata[token].length;
        bucketIndex = (runtime - minRuntime) / bucketSize;
    }

    /// Set runtime yields in floating point
    function setRuntimeYieldsFP(address token, uint256[] memory yieldsFP)
        external
        onlyOwner
    {
        BondBucketMetadata[] storage bondMetas = bondBucketMetadata[token];
        for(uint i; bondMetas.length > i; i++) {
            bondMetas[i].runtimeYieldFP = yieldsFP[i];
        }
    }

    /// Set runtime weights in floating point
    function setRuntimeWeights(address token, uint256[] memory weights)
        external
    {
        require(
            isTokenActivator(msg.sender),
            "not autorized to set runtime weights"
        );

        BondBucketMetadata[] storage bondMetas = bondBucketMetadata[token];

        if (bondMetas.length == 0) {
            // we are initializing

            uint256 hourlyYieldFP = (110 * FP32) / 100 / (24 * 365);
            uint256 bucketSize = diffMaxMinRuntime / weights.length;

            for (uint i; weights.length > i; i++) {
                uint256 runtime = minRuntime + bucketSize * i;
                bondMetas.push(BondBucketMetadata({
                        runtimeYieldFP: hourlyYieldFP * runtime / (1 hours),
                                lastBought: block.timestamp,
                                lastWithdrawn: block.timestamp,
                                yieldLastUpdated: block.timestamp,
                                buyingSpeed: 1,
                                withdrawingSpeed: 1,
                                runtimeWeight: weights[i],
                                totalLending: 0
                                }));
            }
        } else {
            require(weights.length == bondMetas.length, "Weights don't match buckets");
            for (uint i; weights.length > i; i++) {
                bondMetas[i].runtimeWeight = weights[i];
            }
        }
    }

    /// Set miniumum runtime
    function setMinRuntime(uint256 runtime) external onlyOwner {
        require(runtime > 1 hours, "Min runtime needs to be at least 1 hour");
        require(
            maxRuntime > runtime,
            "Min runtime must be smaller than max runtime"
        );
        minRuntime = runtime;
    }

    /// Set maximum runtime
    function setMaxRuntime(uint256 runtime) external onlyOwner {
        require(
            runtime > minRuntime,
            "Max runtime must be greater than min runtime"
        );
        maxRuntime = runtime;
    }
}
