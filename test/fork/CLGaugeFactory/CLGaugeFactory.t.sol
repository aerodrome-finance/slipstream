pragma solidity ^0.7.6;
pragma abicoder v2;

import "../BaseForkFixture.sol";

abstract contract CLGaugeFactoryForkTest is BaseForkFixture {
    uint256 public MAX_BPS = 10_000;
    CLPool public pool;
    CLGauge public gauge;

    function setUp() public virtual override {
        blockNumber = 36574920;
        super.setUp();

        pool = CLPool(
            poolFactory.createPool({
                tokenA: address(token0),
                tokenB: address(token1),
                tickSpacing: TICK_SPACING_60,
                sqrtPriceX96: encodePriceSqrt(1, 1)
            })
        );
        vm.prank(voter.governor());
        gauge = CLGauge(payable(voter.createGauge({_poolFactory: address(poolFactory), _pool: address(pool)})));
    }

    function test_InitialState() public view {
        assertEq(gaugeFactory.voter(), address(voter));
        assertEq(gaugeFactory.implementation(), address(gaugeImplementation));
        assertEq(gaugeFactory.nft(), address(nft));
        assertEq(gaugeFactory.notifyAdmin(), users.owner);
        assertEq(gaugeFactory.MAX_BPS(), MAX_BPS);
        assertEq(gaugeFactory.minter(), address(minter));
        assertEq(gaugeFactory.rewardToken(), address(rewardToken));
        assertEq(gaugeFactory.emissionAdmin(), users.owner);
        assertEq(gaugeFactory.defaultCap(), 100);
        assertEq(gaugeFactory.weeklyEmissions(), 0);
        assertEq(gaugeFactory.activePeriod(), 0);
        assertTrue(gaugeFactory.isGauge(address(gauge)));
        assertEq(gaugeFactory.redistributor(), address(redistributor));
        assertEq(address(gaugeFactory.legacyCLGaugeFactory()), address(legacyGaugeFactory));
    }
}
