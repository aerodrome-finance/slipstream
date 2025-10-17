// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {TransferHelper} from "contracts/periphery/libraries/TransferHelper.sol";
import {ProtocolTimeLibrary} from "contracts/libraries/ProtocolTimeLibrary.sol";

import {IRedistributor} from "contracts/gauge/interfaces/IRedistributor.sol";
import {ICLGaugeFactory} from "contracts/gauge/interfaces/ICLGaugeFactory.sol";
import {ICLGauge} from "contracts/gauge/interfaces/ICLGauge.sol";
import {IVoter} from "contracts/core/interfaces/IVoter.sol";
import {IVotingEscrow} from "contracts/core/interfaces/IVotingEscrow.sol";

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

    /// @inheritdoc IRedistributor
    function notifyRewardWithoutClaim(address _gauge, uint256 _amount) external override onlyOwner nonReentrant {
        require(_amount != 0, "ZR");
        require(voter.isGauge({_gauge: _gauge}), "NG");

        TransferHelper.safeTransferFrom({token: rewardToken, from: msg.sender, to: address(this), value: _amount});
        TransferHelper.safeApprove({token: rewardToken, to: _gauge, value: _amount});
        ICLGauge(_gauge).notifyRewardWithoutClaim({amount: _amount});

        emit NotifyRewardWithoutClaim({gauge: _gauge, amount: _amount});
    }

    /// @inheritdoc IRedistributor
    function setArtProxy(address _proxy) external override onlyOwner nonReentrant {
        IVotingEscrow(escrow).setArtProxy({_proxy: _proxy});

        emit SetArtProxy({proxy: _proxy});
    }

    /// @inheritdoc IRedistributor
    function toggleSplit(address _account, bool _bool) external override onlyOwner nonReentrant {
        IVotingEscrow(escrow).toggleSplit({_account: _account, _bool: _bool});

        emit ToggleSplit({account: _account, enabled: _bool});
    }

    /// @inheritdoc IRedistributor
    function transferPermissions(address _newRedistributor) external override onlyOwner nonReentrant {
        require(_newRedistributor != address(0), "ZA");
        IVotingEscrow(escrow).setTeam({_team: _newRedistributor});
        ICLGaugeFactory(ICLGaugeFactory(gaugeFactory).legacyCLGaugeFactory()).setNotifyAdmin({_admin: _newRedistributor});

        emit PermissionsTransferred({redistributor: address(this), newRedistributor: _newRedistributor});
    }
}
