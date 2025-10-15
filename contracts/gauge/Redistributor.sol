// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {TransferHelper} from "contracts/periphery/libraries/TransferHelper.sol";
import {ProtocolTimeLibrary} from "contracts/libraries/ProtocolTimeLibrary.sol";

import {IRedistributor} from "contracts/gauge/interfaces/IRedistributor.sol";
import {ICLGaugeFactory} from "contracts/gauge/interfaces/ICLGaugeFactory.sol";
import {IVoter} from "contracts/core/interfaces/IVoter.sol";

/// @title Redistributor
/// @notice Manages the redistribution of excess emissions to Aerodrome gauges
contract Redistributor is IRedistributor, Ownable, ReentrancyGuard {
    /// @inheritdoc IRedistributor
    IVoter public immutable override voter;
    /// @inheritdoc IRedistributor
    address public immutable override minter;
    /// @inheritdoc IRedistributor
    address public immutable override escrow;
    /// @inheritdoc IRedistributor
    address public immutable override gaugeFactory;
    /// @inheritdoc IRedistributor
    address public immutable override rewardToken;

    /// @inheritdoc IRedistributor
    mapping(uint256 => uint256) public override totalWeight;
    /// @inheritdoc IRedistributor
    mapping(uint256 => uint256) public override totalEmissions;
    /// @inheritdoc IRedistributor
    mapping(uint256 => mapping(address => bool)) public override isExcluded;

    constructor(address _voter, address _gaugeFactory, address _initialOwner) {
        voter = IVoter(_voter);
        minter = IVoter(_voter).minter();
        escrow = address(IVoter(_voter).ve());
        gaugeFactory = _gaugeFactory;
        rewardToken = ICLGaugeFactory(_gaugeFactory).rewardToken();

        transferOwnership({newOwner: _initialOwner});
    }

    /// @inheritdoc IRedistributor
    function deposit(uint256 _amount) external override nonReentrant {
        require(voter.isGauge({_gauge: msg.sender}), "NG");

        uint256 epochStart = ProtocolTimeLibrary.epochStart({timestamp: block.timestamp});
        if (totalWeight[epochStart] == 0) {
            totalWeight[epochStart] = voter.totalWeight();
        }
        isExcluded[epochStart][msg.sender] = true;

        if (totalEmissions[epochStart] == 0) {
            address pool = voter.poolForGauge({_gauge: msg.sender});
            totalWeight[epochStart] -= voter.weights({_pool: pool});
            TransferHelper.safeTransferFrom({token: rewardToken, from: msg.sender, to: address(this), value: _amount});
            emit Deposited({gauge: msg.sender, to: address(this), amount: _amount});
        } else {
            /// @dev If this epoch's redistribution has already started, forward emissions to minter
            TransferHelper.safeTransferFrom({token: rewardToken, from: msg.sender, to: minter, value: _amount});
            emit Deposited({gauge: msg.sender, to: minter, amount: _amount});
        }
    }
}
