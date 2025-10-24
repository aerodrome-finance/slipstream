pragma solidity ^0.7.6;
pragma abicoder v2;

import "../BaseForkFixture.sol";

abstract contract CLGaugeForkTest is BaseForkFixture {
    CLPool public pool;
    CLGauge public gauge;

    function test_InitialState() public view {
        assertEq(address(gauge.nft()), address(nft));
        assertEq(address(gauge.voter()), address(voter));
        assertEq(address(gauge.pool()), address(pool));
        assertEq(address(gauge.gaugeFactory()), address(gaugeFactory));
        assertNotEq(gauge.feesVotingReward(), address(0));
        assertEq(gauge.periodFinish(), 0);
        assertEq(gauge.rewardRate(), 0);
        assertEq(gauge.rewardRateByEpoch(block.timestamp), 0);
        assertEq(gauge.fees0(), 0);
        assertEq(gauge.fees1(), 0);
        assertEq(gauge.token0(), address(token0));
        assertEq(gauge.token1(), address(token1));
        assertEq(gauge.tickSpacing(), pool.tickSpacing());
        assertEq(gauge.tickSpacing(), TICK_SPACING_60);
        assertEq(gauge.left(), 0);
        assertEq(gauge.rewardToken(), address(rewardToken));
        assertTrue(gauge.isPool());
        assertEq(gauge.rewardsByEpoch(block.timestamp), 0);
    }
}
