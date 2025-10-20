// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;
pragma abicoder v2;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {TransferHelper} from "contracts/periphery/libraries/TransferHelper.sol";
import {ProtocolTimeLibrary} from "contracts/libraries/ProtocolTimeLibrary.sol";

import {IRedistributor} from "contracts/gauge/interfaces/IRedistributor.sol";
import {IUpkeepManager} from "contracts/gauge/interfaces/IUpkeepManager.sol";
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
    address public override upkeepManager;
    /// @inheritdoc IRedistributor
    address public override keeper;
    /// @inheritdoc IRedistributor
    uint256 public override activePeriod;

    /// @inheritdoc IRedistributor
    mapping(uint256 => uint256) public override totalWeight;
    /// @inheritdoc IRedistributor
    mapping(uint256 => uint256) public override totalEmissions;
    /// @inheritdoc IRedistributor
    mapping(uint256 => mapping(address => bool)) public override isExcluded;
    /// @inheritdoc IRedistributor
    mapping(uint256 => mapping(address => bool)) public override isRedistributed;

    constructor(address _voter, address _gaugeFactory, address _upkeepManager, address _initialOwner) {
        voter = IVoter(_voter);
        minter = IVoter(_voter).minter();
        escrow = address(IVoter(_voter).ve());
        gaugeFactory = _gaugeFactory;
        rewardToken = ICLGaugeFactory(_gaugeFactory).rewardToken();
        upkeepManager = _upkeepManager;

        transferOwnership({newOwner: _initialOwner});
    }

    modifier onlyUpkeepOrKeeper() {
        if (!IUpkeepManager(upkeepManager).isUpkeep({_account: msg.sender})) {
            require(msg.sender == keeper, "NA");
        }
        _;
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
    function redistribute(address[] memory _gauges) external override onlyUpkeepOrKeeper nonReentrant {
        uint256 epochStart = ProtocolTimeLibrary.epochStart({timestamp: block.timestamp});
        require(block.timestamp >= epochStart + 10 minutes, "TS");

        // @dev Early return if there are no emissions to redistribute
        uint256 _totalEmissions = _updateTotalEmissions({_epochStart: epochStart});
        if (_totalEmissions == 0) return;

        uint256 _totalWeight = _updateTotalWeight({_epochStart: epochStart});

        address gauge;
        uint256 length = _gauges.length;
        for (uint256 i = 0; i < length; i++) {
            gauge = _gauges[i];
            require(voter.isGauge({_gauge: gauge}), "NG");
            _redistribute({
                _gauge: gauge,
                _pool: voter.poolForGauge({_gauge: gauge}),
                _totalWeight: _totalWeight,
                _totalEmissions: _totalEmissions,
                _epochStart: epochStart
            });
        }
    }

    /// @inheritdoc IRedistributor
    function redistribute(uint256 _start, uint256 _end) external override onlyUpkeepOrKeeper nonReentrant {
        uint256 epochStart = ProtocolTimeLibrary.epochStart({timestamp: block.timestamp});
        require(block.timestamp >= epochStart + 10 minutes, "TS");

        // @dev Early return if there are no emissions to redistribute
        uint256 _totalEmissions = _updateTotalEmissions({_epochStart: epochStart});
        if (_totalEmissions == 0) return;

        uint256 _totalWeight = _updateTotalWeight({_epochStart: epochStart});

        address pool;
        uint256 length = voter.length();
        _end = _end < length ? _end : length;
        for (uint256 i = 0; i < _end - _start; i++) {
            pool = voter.pools({_index: i + _start});
            _redistribute({
                _gauge: voter.gauges({_pool: pool}),
                _pool: pool,
                _totalWeight: _totalWeight,
                _totalEmissions: _totalEmissions,
                _epochStart: epochStart
            });
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
    function setUpkeepManager(address _upkeepManager) external override onlyOwner nonReentrant {
        require(_upkeepManager != address(0), "ZA");
        upkeepManager = _upkeepManager;

        emit SetUpkeepManager({upkeepManager: _upkeepManager});
    }

    /// @inheritdoc IRedistributor
    function setKeeper(address _keeper) external override onlyOwner nonReentrant {
        require(_keeper != address(0), "ZA");
        keeper = _keeper;

        emit SetKeeper({keeper: _keeper});
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

    /**
     * @notice Redistributes the recycled emissions to the given gauge, proportionally to its voting weight
     * @dev Assumes the specified gauge is linked to the pool
     * @param _gauge The gauge to redistribute the emissions to
     * @param _pool The pool linked to the given gauge
     * @param _totalWeight The total voting weight for the given epoch
     * @param _totalEmissions The total amount of emissions to redistribute in the given epoch
     * @param _epochStart The start of the epoch to redistribute the emissions in
     */
    function _redistribute(
        address _gauge,
        address _pool,
        uint256 _totalWeight,
        uint256 _totalEmissions,
        uint256 _epochStart
    ) internal {
        if (!isExcluded[_epochStart][_gauge] && !isRedistributed[_epochStart][_gauge]) {
            isRedistributed[_epochStart][_gauge] = true;

            uint256 gaugeWeight = voter.weights({_pool: _pool});
            uint256 gaugeEmissions = _totalEmissions * gaugeWeight / _totalWeight;
            /// @dev Skip gauge if no emissions to redistribute
            if (gaugeEmissions == 0) return;

            if (voter.isAlive({_gauge: _gauge})) {
                if (ICLGaugeFactory(gaugeFactory).isGauge({_gauge: _gauge})) {
                    uint256 prevEmissions = ICLGauge(_gauge).rewardsByEpoch({_epochStart: _epochStart});
                    uint256 maxEmissions = ICLGaugeFactory(gaugeFactory).calculateMaxEmissions({_gauge: _gauge});
                    /// @dev Forward emissions to minter if distribute failed for a gauge with emission cap
                    ///      or if the emission cap has already been exceeded
                    if (prevEmissions == 0 || prevEmissions >= maxEmissions) {
                        TransferHelper.safeTransfer({token: rewardToken, to: minter, value: gaugeEmissions});
                        return;
                    }

                    // @dev If redistributed emissions exceed the emission cap, forward excess to minter
                    maxEmissions -= prevEmissions;
                    if (gaugeEmissions > maxEmissions) {
                        TransferHelper.safeTransfer({
                            token: rewardToken,
                            to: minter,
                            value: gaugeEmissions - maxEmissions
                        });
                        gaugeEmissions = maxEmissions;
                    }
                }

                TransferHelper.safeApprove({token: rewardToken, to: _gauge, value: gaugeEmissions});
                ICLGauge(_gauge).notifyRewardWithoutClaim({amount: gaugeEmissions});
                emit Redistributed({sender: msg.sender, gauge: _gauge, amount: gaugeEmissions});
            } else {
                /// @dev If the gauge is killed but has a non-zero voting weight, forward emissions to minter
                TransferHelper.safeTransfer({token: rewardToken, to: minter, value: gaugeEmissions});
            }
        }
    }

    /**
     * @notice Fetches and stores the amount of emissions to be redistributed in a given epoch
     * @dev The emissions amount and active period are only recorded once per epoch
     * @param _epochStart The epoch to fetch the emissions for
     * @return The amount of emissions to redistribute in the given epoch
     */
    function _updateTotalEmissions(uint256 _epochStart) internal returns (uint256) {
        uint256 _totalEmissions;
        if (activePeriod != _epochStart) {
            _totalEmissions = IERC20(rewardToken).balanceOf(address(this));
            totalEmissions[_epochStart] = _totalEmissions;
            activePeriod = _epochStart;
        } else {
            _totalEmissions = totalEmissions[_epochStart];
        }

        return _totalEmissions;
    }

    /**
     * @notice Fetches and stores the total voting weight for the given epoch, if not already stored
     * @dev The total weight is only recorded once per epoch
     * @param _epochStart The epoch to fetch the emissions for
     * @return The total voting weight for the given epoch
     */
    function _updateTotalWeight(uint256 _epochStart) internal returns (uint256) {
        uint256 _totalWeight = totalWeight[_epochStart];
        if (_totalWeight == 0) {
            _totalWeight = voter.totalWeight();
            totalWeight[_epochStart] = _totalWeight;
        }

        return _totalWeight;
    }
}
