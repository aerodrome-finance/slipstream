// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import {UniswapV3Factory} from "contracts/core/UniswapV3Factory.sol";
import {CLGaugeFactory} from "contracts/gauge/CLGaugeFactory.sol";
import {IVoter} from "contracts/core/interfaces/IVoter.sol";
import {IFactoryRegistry} from "contracts/core/interfaces/IFactoryRegistry.sol";
import {ICLGauge} from "contracts/gauge/interfaces/ICLGauge.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "contracts/core/interfaces/IUniswapV3Pool.sol";
import {IVotingRewardsFactory} from "contracts/test/interfaces/IVotingRewardsFactory.sol";

contract MockVoter is IVoter {
    // mock addresses used for testing gauge creation, a copy is stored in Constants.sol
    address public forwarder = address(11);

    // Rewards are released over 7 days
    uint256 internal constant DURATION = 7 days;

    /// @dev pool => gauge
    mapping(address => address) public override gauges;
    /// @dev gauge => isAlive
    mapping(address => bool) public override isAlive;
    mapping(address => address) public override gaugeToFees;
    mapping(address => address) public override gaugeToBribes;

    IERC20 internal immutable rewardToken;
    IFactoryRegistry public immutable factoryRegistry;

    constructor(address _rewardToken, address _factoryRegistry) {
        rewardToken = IERC20(_rewardToken);
        factoryRegistry = IFactoryRegistry(_factoryRegistry);
    }

    function createGauge(address _poolFactory, address _pool) external override returns (address) {
        require(factoryRegistry.isPoolFactoryApproved(_poolFactory));
        (address votingRewardsFactory, address gaugeFactory) = factoryRegistry.factoriesToPoolFactory(_poolFactory);

        /// @dev mimic flow in real voter, note that feesVotingReward and bribeVotingReward are unused mocks
        address[] memory rewards = new address[](2);
        rewards[0] = IUniswapV3Pool(_pool).token0();
        rewards[1] = IUniswapV3Pool(_pool).token1();
        (address feesVotingReward, address bribeVotingReward) =
            IVotingRewardsFactory(votingRewardsFactory).createRewards(forwarder, rewards);

        address gauge =
            CLGaugeFactory(gaugeFactory).createGauge(forwarder, _pool, feesVotingReward, address(rewardToken), true);
        require(UniswapV3Factory(_poolFactory).isPair(_pool));
        isAlive[gauge] = true;
        gauges[_pool] = gauge;
        gaugeToFees[gauge] = feesVotingReward;
        gaugeToBribes[gauge] = bribeVotingReward;
        return gauge;
    }

    function distribute(address gauge) external override {
        uint256 _claimable = rewardToken.balanceOf(address(this));
        if (_claimable > ICLGauge(gauge).left() && _claimable > DURATION) {
            rewardToken.approve(gauge, _claimable);
            ICLGauge(gauge).notifyRewardAmount(rewardToken.balanceOf(address(this)));
        }
    }
}