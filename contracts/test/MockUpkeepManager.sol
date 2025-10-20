// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {IUpkeepManager} from "contracts/gauge/interfaces/IUpkeepManager.sol";

contract MockUpkeepManager is IUpkeepManager {
    mapping(address => bool) public override isUpkeep;

    function setUpkeep(address _upkeep, bool _state) external {
        isUpkeep[_upkeep] = _state;
    }
}
