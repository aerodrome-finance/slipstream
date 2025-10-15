// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {IMinter} from "contracts/core/interfaces/IMinter.sol";

contract MockMinter is IMinter {
    address public immutable override aero;

    constructor(address _aero) {
        aero = _aero;
    }

    function activePeriod() external pure override returns (uint256) {
        revert("Not implemented");
    }

    function tailEmissionRate() external pure override returns (uint256) {
        revert("Not implemented");
    }

    function updatePeriod() external pure override returns (uint256) {
        revert("Not implemented");
    }

    function weekly() external pure override returns (uint256) {
        revert("Not implemented");
    }
}
