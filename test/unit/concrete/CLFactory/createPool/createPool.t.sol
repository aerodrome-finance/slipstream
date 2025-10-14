pragma solidity ^0.7.6;
pragma abicoder v2;

import "../CLFactory.t.sol";

contract CreatePoolUnitConcreteTest is CLFactoryTest {
    function test_RevertWhen_BothTokensHaveTheSameAddress() external {
        // It should revert
        vm.expectRevert();
        poolFactory.createPool({
            tokenA: TEST_TOKEN_0,
            tokenB: TEST_TOKEN_0,
            tickSpacing: TICK_SPACING_LOW,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });
    }

    modifier whenBothTokensDoNotHaveTheSameAddress() {
        _;
    }

    function test_RevertWhen_OneOfTheTokensIsTheAddressZero() external whenBothTokensDoNotHaveTheSameAddress {
        // It should revert
        vm.expectRevert();
        poolFactory.createPool({
            tokenA: TEST_TOKEN_0,
            tokenB: address(0),
            tickSpacing: TICK_SPACING_LOW,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });

        vm.expectRevert();
        poolFactory.createPool({
            tokenA: address(0),
            tokenB: TEST_TOKEN_0,
            tickSpacing: TICK_SPACING_LOW,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });

        vm.expectRevert();
        poolFactory.createPool({
            tokenA: address(0),
            tokenB: address(0),
            tickSpacing: TICK_SPACING_LOW,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });
    }

    modifier whenNoneOfTheTokensIsTheAddressZero() {
        _;
    }

    function test_RevertWhen_TheTickSpacingIsNotEnabled()
        external
        whenBothTokensDoNotHaveTheSameAddress
        whenNoneOfTheTokensIsTheAddressZero
    {
        // It should revert
        vm.expectRevert();
        poolFactory.createPool({
            tokenA: TEST_TOKEN_0,
            tokenB: TEST_TOKEN_1,
            tickSpacing: 250,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });
    }

    modifier whenTheTickSpacingIsEnabled() {
        _;
    }

    function test_RevertWhen_ThePoolAlreadyExists()
        external
        whenBothTokensDoNotHaveTheSameAddress
        whenNoneOfTheTokensIsTheAddressZero
        whenTheTickSpacingIsEnabled
    {
        // It should revert
        legacyPoolFactory.createPool({
            tokenA: TEST_TOKEN_0,
            tokenB: TEST_TOKEN_1,
            tickSpacing: TICK_SPACING_STABLE,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });

        vm.expectRevert();
        legacyPoolFactory.createPool({
            tokenA: TEST_TOKEN_0,
            tokenB: TEST_TOKEN_1,
            tickSpacing: TICK_SPACING_STABLE,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });
    }

    modifier whenThePoolDoesNotExist() {
        _;
    }

    function test_WhenThePoolDoesNotExistInTheLegacyClFactory()
        external
        whenBothTokensDoNotHaveTheSameAddress
        whenNoneOfTheTokensIsTheAddressZero
        whenTheTickSpacingIsEnabled
        whenThePoolDoesNotExist
    {
        // It should create the pool
        // It should initialize the pool
        // It should add the new pool to the pool array
        // It should create a reference for the pool in the pool mappings
        // It should flag that the new pool exists
        // It should emit a {PoolCreated} event
        address pool = createAndCheckPool({
            factory: poolFactory,
            token0: TEST_TOKEN_0,
            token1: TEST_TOKEN_1,
            tickSpacing: TICK_SPACING_STABLE,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });
        assertEqUint(poolFactory.getSwapFee(pool), 100);
    }

    function test_WhenThePoolDoesNotExistInTheLegacyClFactory_ReversedTokens()
        external
        whenBothTokensDoNotHaveTheSameAddress
        whenNoneOfTheTokensIsTheAddressZero
        whenTheTickSpacingIsEnabled
        whenThePoolDoesNotExist
    {
        // It should create the pool
        // It should initialize the pool
        // It should add the new pool to the pool array
        // It should create a reference for the pool in the pool mappings
        // It should flag that the new pool exists
        // It should emit a {PoolCreated} event
        createAndCheckPool({
            factory: poolFactory,
            token0: TEST_TOKEN_1,
            token1: TEST_TOKEN_0,
            tickSpacing: TICK_SPACING_LOW,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });
    }

    function test_WhenThePoolDoesNotExistInTheLegacyClFactory_TickSpacingLow()
        external
        whenBothTokensDoNotHaveTheSameAddress
        whenNoneOfTheTokensIsTheAddressZero
        whenTheTickSpacingIsEnabled
        whenThePoolDoesNotExist
    {
        // It should create the pool
        // It should initialize the pool
        // It should add the new pool to the pool array
        // It should create a reference for the pool in the pool mappings
        // It should flag that the new pool exists
        // It should emit a {PoolCreated} event
        address pool = createAndCheckPool({
            factory: poolFactory,
            token0: TEST_TOKEN_0,
            token1: TEST_TOKEN_1,
            tickSpacing: TICK_SPACING_LOW,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });
        assertEqUint(poolFactory.getSwapFee(pool), 500);
    }

    function test_WhenThePoolDoesNotExistInTheLegacyClFactory_TickSpacingMedium()
        external
        whenBothTokensDoNotHaveTheSameAddress
        whenNoneOfTheTokensIsTheAddressZero
        whenTheTickSpacingIsEnabled
        whenThePoolDoesNotExist
    {
        // It should create the pool
        // It should initialize the pool
        // It should add the new pool to the pool array
        // It should create a reference for the pool in the pool mappings
        // It should flag that the new pool exists
        // It should emit a {PoolCreated} event
        address pool = createAndCheckPool({
            factory: poolFactory,
            token0: TEST_TOKEN_0,
            token1: TEST_TOKEN_1,
            tickSpacing: TICK_SPACING_MEDIUM,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });
        assertEqUint(poolFactory.getSwapFee(pool), 500);

        CLGauge gauge = CLGauge(payable(voter.createGauge({_poolFactory: address(poolFactory), _pool: address(pool)})));
        address feesVotingReward = voter.gaugeToFees(address(gauge));
        assertEq(address(gauge.pool()), address(pool));
        assertEq(gauge.feesVotingReward(), address(feesVotingReward));
        assertEq(gauge.rewardToken(), address(rewardToken));
        assertTrue(gauge.isPool());
    }

    function test_WhenThePoolDoesNotExistInTheLegacyClFactory_TickSpacingHigh()
        external
        whenBothTokensDoNotHaveTheSameAddress
        whenNoneOfTheTokensIsTheAddressZero
        whenTheTickSpacingIsEnabled
        whenThePoolDoesNotExist
    {
        // It should create the pool
        // It should initialize the pool
        // It should add the new pool to the pool array
        // It should create a reference for the pool in the pool mappings
        // It should flag that the new pool exists
        // It should emit a {PoolCreated} event
        address pool = createAndCheckPool({
            factory: poolFactory,
            token0: TEST_TOKEN_0,
            token1: TEST_TOKEN_1,
            tickSpacing: TICK_SPACING_HIGH,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });
        assertEqUint(poolFactory.getSwapFee(pool), 3_000);

        CLGauge gauge = CLGauge(payable(voter.createGauge({_poolFactory: address(poolFactory), _pool: address(pool)})));
        address feesVotingReward = voter.gaugeToFees(address(gauge));
        assertEq(address(gauge.pool()), address(pool));
        assertEq(gauge.feesVotingReward(), address(feesVotingReward));
        assertEq(gauge.rewardToken(), address(rewardToken));
        assertTrue(gauge.isPool());
    }

    function test_WhenThePoolDoesNotExistInTheLegacyClFactory_TickSpacingVolatile()
        external
        whenBothTokensDoNotHaveTheSameAddress
        whenNoneOfTheTokensIsTheAddressZero
        whenTheTickSpacingIsEnabled
        whenThePoolDoesNotExist
    {
        // It should create the pool
        // It should initialize the pool
        // It should add the new pool to the pool array
        // It should create a reference for the pool in the pool mappings
        // It should flag that the new pool exists
        // It should emit a {PoolCreated} event
        address pool = createAndCheckPool({
            factory: poolFactory,
            token0: TEST_TOKEN_0,
            token1: TEST_TOKEN_1,
            tickSpacing: TICK_SPACING_VOLATILE,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });
        assertEqUint(poolFactory.getSwapFee(pool), 10_000);

        CLGauge gauge = CLGauge(payable(voter.createGauge({_poolFactory: address(poolFactory), _pool: address(pool)})));
        address feesVotingReward = voter.gaugeToFees(address(gauge));
        assertEq(address(gauge.pool()), address(pool));
        assertEq(gauge.feesVotingReward(), address(feesVotingReward));
        assertEq(gauge.rewardToken(), address(rewardToken));
        assertTrue(gauge.isPool());
    }

    modifier whenThePoolAlreadyExistsInTheLegacyClFactory() {
        legacyPoolFactory.createPool({
            tokenA: TEST_TOKEN_0,
            tokenB: TEST_TOKEN_1,
            tickSpacing: TICK_SPACING_STABLE,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });
        _;
    }

    function test_RevertWhen_TheCallerIsNotTheOwner()
        external
        whenBothTokensDoNotHaveTheSameAddress
        whenNoneOfTheTokensIsTheAddressZero
        whenTheTickSpacingIsEnabled
        whenThePoolDoesNotExist
        whenThePoolAlreadyExistsInTheLegacyClFactory
    {
        // It should revert
        vm.startPrank(users.charlie);
        vm.expectRevert();
        poolFactory.createPool({
            tokenA: TEST_TOKEN_0,
            tokenB: TEST_TOKEN_1,
            tickSpacing: TICK_SPACING_STABLE,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });
    }

    function test_WhenTheCallerIsTheOwner()
        external
        whenBothTokensDoNotHaveTheSameAddress
        whenNoneOfTheTokensIsTheAddressZero
        whenTheTickSpacingIsEnabled
        whenThePoolDoesNotExist
        whenThePoolAlreadyExistsInTheLegacyClFactory
    {
        // It should create the pool
        // It should initialize the pool
        // It should add the new pool to the pool array
        // It should create a reference for the pool in the pool mappings
        // It should flag that the new pool exists
        // It should emit a {PoolCreated} event
        vm.startPrank(poolFactory.owner());
        address pool = createAndCheckPool({
            factory: poolFactory,
            token0: TEST_TOKEN_0,
            token1: TEST_TOKEN_1,
            tickSpacing: TICK_SPACING_STABLE,
            sqrtPriceX96: encodePriceSqrt(1, 1)
        });
        assertEqUint(poolFactory.getSwapFee(pool), 100);
    }
}
