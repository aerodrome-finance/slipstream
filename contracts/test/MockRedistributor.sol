// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRedistributor} from "contracts/gauge/interfaces/IRedistributor.sol";

contract MockRedistributor is IRedistributor {
    address public rewardToken;

    constructor(address _rewardToken) {
        rewardToken = _rewardToken;
    }

    function deposit(uint256 _amount) external override {
        IERC20(rewardToken).transferFrom(msg.sender, address(this), _amount);
    }
}
