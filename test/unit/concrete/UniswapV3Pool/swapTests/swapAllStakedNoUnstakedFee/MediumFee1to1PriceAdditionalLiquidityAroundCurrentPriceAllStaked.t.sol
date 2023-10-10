pragma solidity ^0.7.6;
pragma abicoder v2;

import {UniswapV3PoolSwapAllStakedNoUnstakeFeeTest, CLGauge} from "./UniswapV3PoolSwapAllStakedNoUnstakeFee.t.sol";
import {IUniswapV3Pool} from "contracts/core/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "contracts/periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from "contracts/core/libraries/TickMath.sol";

contract MediumFee1to1PriceAdditionalLiquidityAroundCurrentPriceAllStakedTest is
    UniswapV3PoolSwapAllStakedNoUnstakeFeeTest
{
    function setUp() public override {
        super.setUp();

        int24 tickSpacing = TICK_SPACING_60;

        string memory poolName = ".medium_fee_1to1_price_additional_liquidity_around_current_price";
        address pool =
            poolFactory.createPool({tokenA: address(token0), tokenB: address(token1), tickSpacing: tickSpacing});

        uint160 startingPrice = encodePriceSqrt(1, 1);
        IUniswapV3Pool(pool).initialize(startingPrice);

        uint128 liquidity = 2e18;

        stakedPositions.push(
            Position({tickLower: getMinTick(tickSpacing), tickUpper: getMaxTick(tickSpacing), liquidity: liquidity})
        );

        stakedPositions.push(
            Position({tickLower: getMinTick(tickSpacing), tickUpper: -tickSpacing, liquidity: liquidity})
        );

        stakedPositions.push(
            Position({tickLower: tickSpacing, tickUpper: getMaxTick(tickSpacing), liquidity: liquidity})
        );

        gauge = CLGauge(voter.gauges(pool));

        vm.stopPrank();

        // set zero unstaked fee
        vm.prank(users.feeManager);
        customUnstakedFeeModule.setCustomFee(pool, 420);

        uint256 positionsLength = stakedPositions.length;

        for (uint256 i = 0; i < positionsLength; i++) {
            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                startingPrice,
                TickMath.getSqrtRatioAtTick(stakedPositions[i].tickLower),
                TickMath.getSqrtRatioAtTick(stakedPositions[i].tickUpper),
                stakedPositions[i].liquidity
            );

            vm.startPrank(users.alice);
            uint256 tokenId = nftCallee.mintNewCustomRangePositionForUserWithCustomTickSpacing(
                amount0 + 1,
                amount1 + 1,
                stakedPositions[i].tickLower,
                stakedPositions[i].tickUpper,
                tickSpacing,
                users.alice
            );
            nft.approve(address(gauge), tokenId);
            gauge.deposit(tokenId);
        }

        uint256 poolBalance0 = token0.balanceOf(pool);
        uint256 poolBalance1 = token1.balanceOf(pool);

        (uint160 sqrtPriceX96, int24 tick,,,,) = IUniswapV3Pool(pool).slot0();

        poolSetup = PoolSetup({
            poolName: poolName,
            pool: pool,
            gauge: address(gauge),
            poolBalance0: poolBalance0,
            poolBalance1: poolBalance1,
            sqrtPriceX96: sqrtPriceX96,
            tick: tick
        });
    }
}
