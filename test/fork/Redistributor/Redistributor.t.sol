pragma solidity ^0.7.6;
pragma abicoder v2;

import "../BaseForkFixture.sol";

abstract contract RedistributorForkTest is BaseForkFixture {
    CLPool public pool;
    CLPool public pool2;
    CLPool public pool3;
    CLGauge public gauge;
    CLGauge public gauge2;
    CLGauge public gauge3;

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
        pool2 = CLPool(
            poolFactory.createPool({
                tokenA: address(token0),
                tokenB: address(token1),
                tickSpacing: TICK_SPACING_200,
                sqrtPriceX96: encodePriceSqrt(1, 1)
            })
        );
        pool3 = CLPool(
            poolFactory.createPool({
                tokenA: address(token0),
                tokenB: address(token1),
                tickSpacing: TICK_SPACING_10,
                sqrtPriceX96: encodePriceSqrt(1, 1)
            })
        );

        vm.startPrank(voter.governor());
        gauge = CLGauge(payable(voter.createGauge({_poolFactory: address(poolFactory), _pool: address(pool)})));
        gauge2 = CLGauge(payable(voter.createGauge({_poolFactory: address(poolFactory), _pool: address(pool2)})));
        gauge3 = CLGauge(payable(voter.createGauge({_poolFactory: address(poolFactory), _pool: address(pool3)})));
        vm.stopPrank();
    }

    function test_InitialState() public view {
        assertEq(redistributor.owner(), users.owner);
        assertEq(address(redistributor.voter()), address(voter));
        assertEq(redistributor.minter(), address(minter));
        assertEq(redistributor.escrow(), address(escrow));
        assertEq(redistributor.gaugeFactory(), address(gaugeFactory));
        assertEq(redistributor.rewardToken(), address(rewardToken));
        assertEq(redistributor.upkeepManager(), address(upkeepManager));
    }
}
