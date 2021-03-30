// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Roles.sol";

/// Main characters are for service discovery
/// Whereas roles are for access control
contract RoleAware {
    // we chose not to go with an enum
    // to make this list easy to extend
    uint16 constant FUND_TRANSFERER = 1;
    uint16 constant MARGIN_CALLER = 2;
    uint16 constant BORROWER = 3;
    uint16 constant MARGIN_TRADER = 4;
    uint16 constant FEE_SOURCE = 5;
    uint16 constant LIQUIDATOR = 6;
    uint16 constant AUTHORIZED_FUND_TRADER = 7;
    uint16 constant INCENTIVE_REPORTER = 8;
    uint16 constant TOKEN_ACTIVATOR = 9;
    uint16 constant STAKE_PENALIZER = 10;

    uint16 constant FUND = 101;
    uint16 constant LENDING = 102;
    uint16 constant ROUTER = 103;
    uint16 constant MARGIN_TRADING = 104;
    uint16 constant FEE_CONTROLLER = 105;
    uint16 constant PRICE_CONTROLLER = 106;
    uint16 constant ADMIN = 107;
    uint16 constant INCENTIVE_DISTRIBUTION = 108;
    uint16 constant TOKEN_ADMIN = 109;

    Roles public immutable roles;
    mapping(uint16 => address) public mainCharacterCache;
    mapping(address => mapping(uint16 => bool)) public roleCache;

    constructor(address _roles) {
        roles = Roles(_roles);
    }

    modifier noIntermediary() {
        require(
            msg.sender == tx.origin,
            "Currently no intermediaries allowed for this function call"
        );
        _;
    }

    function updateRoleCache(uint16 role, address contr) public virtual {
        roleCache[contr][role] = roles.getRole(role, contr);
    }

    function updateMainCharacterCache(uint16 role) public virtual {
        mainCharacterCache[role] = roles.mainCharacters(role);
    }

    function fund() internal view returns (address) {
        return mainCharacterCache[FUND];
    }

    function lending() internal view returns (address) {
        return mainCharacterCache[LENDING];
    }

    function router() internal view returns (address) {
        return mainCharacterCache[ROUTER];
    }

    function marginTrading() internal view returns (address) {
        return mainCharacterCache[MARGIN_TRADING];
    }

    function feeController() internal view returns (address) {
        return mainCharacterCache[FEE_CONTROLLER];
    }

    function price() internal view returns (address) {
        return mainCharacterCache[PRICE_CONTROLLER];
    }

    function admin() internal view returns (address) {
        return mainCharacterCache[ADMIN];
    }

    function incentiveDistributor() internal view returns (address) {
        return mainCharacterCache[INCENTIVE_DISTRIBUTION];
    }

    function isBorrower(address contr) internal view returns (bool) {
        return roleCache[contr][BORROWER];
    }

    function isFundTransferer(address contr) internal view returns (bool) {
        return roleCache[contr][FUND_TRANSFERER];
    }

    function isMarginTrader(address contr) internal view returns (bool) {
        return roleCache[contr][MARGIN_TRADER];
    }

    function isFeeSource(address contr) internal view returns (bool) {
        return roleCache[contr][FEE_SOURCE];
    }

    function isMarginCaller(address contr) internal view returns (bool) {
        return roleCache[contr][MARGIN_CALLER];
    }

    function isLiquidator(address contr) internal view returns (bool) {
        return roleCache[contr][LIQUIDATOR];
    }

    function isAuthorizedFundTrader(address contr)
        internal
        view
        returns (bool)
    {
        return roleCache[contr][AUTHORIZED_FUND_TRADER];
    }

    function isIncentiveReporter(address contr) internal view returns (bool) {
        return roleCache[contr][INCENTIVE_REPORTER];
    }

    function isTokenActivator(address contr) internal view returns (bool) {
        return roleCache[contr][TOKEN_ACTIVATOR];
    }

    function isStakePenalizer(address contr) internal view returns (bool) {
        return roles.getRole(STAKE_PENALIZER, contr);
    }
}
