// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import {IVotingEscrow} from "contracts/core/interfaces/IVotingEscrow.sol";

contract MockVotingEscrow is IVotingEscrow {
    address public immutable override team;
    address public override artProxy;

    constructor(address _team) {
        team = _team;
    }

    function createLock(uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    function lockPermanent(uint256) external pure override {
        revert("Not implemented");
    }

    function setTeam(address) external pure override {
        return;
    }

    function setArtProxy(address) external pure override {
        revert("Not implemented");
    }

    function toggleSplit(address, bool) external pure override {
        revert("Not implemented");
    }

    function canSplit(address) external pure override returns (bool) {
        revert("Not implemented");
    }
}
