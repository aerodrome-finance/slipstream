pragma solidity ^0.7.6;
pragma abicoder v2;

import "../CLGauge.t.sol";

contract NotifyRewardAmountIntegrationConcreteTest is CLGaugeForkTest {
    using stdStorage for StdStorage;

    uint256 public WEEKLY_DECAY;
    uint256 public TAIL_START_TIMESTAMP;
    uint256 public beforeTailFork;
    uint256 public afterTailFork;

    function setUp() public override {
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/test/fork/addresses.json"));
        addresses = vm.readFile(path);

        // before tail fork
        beforeTailFork = vm.createSelectFork({urlOrAlias: "base", blockNumber: 12670000});
        _setUp();

        // after tail fork
        afterTailFork = vm.createSelectFork({urlOrAlias: "base", blockNumber: 36820718});
        _setUp();
    }

    function _setUp() internal {
        BaseFixture.setUp();
        WEEKLY_DECAY = gaugeFactory.WEEKLY_DECAY();
        TAIL_START_TIMESTAMP = gaugeFactory.TAIL_START_TIMESTAMP();
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
        skipToNextEpoch(0);
    }

    function test_WhenTheCallerIsNotVoter() external {
        // It should revert with NotVoter
        vm.prank(users.charlie);
        vm.expectRevert(abi.encodePacked("NV"));
        gauge.notifyRewardAmount({_amount: 0});
    }

    modifier whenTheCallerIsVoter() {
        vm.startPrank(address(voter));
        _;
    }

    modifier whenTailEmissionsHaveStarted() {
        vm.selectFork({forkId: afterTailFork});
        _;
    }

    modifier whenTheAmountIsGreaterThanDefinedPercentageOfTailEmissions() {
        _;
    }

    function test_WhenTheCurrentTimestampIsGreaterThanOrEqualToPeriodFinish()
        external
        whenTheCallerIsVoter
        whenTailEmissionsHaveStarted
        whenTheAmountIsGreaterThanDefinedPercentageOfTailEmissions
    {
        // It should return excess emissions to redistributor
        // It should update the reward rate
        // It should cache the updated reward rate for this epoch
        // It should update the rewards deposited for this epoch
        // It should update the period finish timestamp
        // It should emit a {NotifyReward} event
        uint256 weeklyEmissions = (rewardToken.totalSupply() * minter.tailEmissionRate()) / MAX_BPS;
        uint256 maxEmissionRate = gaugeFactory.emissionCaps(address(gauge));
        uint256 maxAmount = maxEmissionRate * weeklyEmissions / MAX_BPS;
        uint256 amount = maxAmount + TOKEN_1;

        deal({token: address(rewardToken), to: address(voter), give: amount});
        rewardToken.approve({spender: address(gauge), amount: amount});

        assertEq(gauge.rewardToken(), address(rewardToken));
        uint256 oldMinterBalance = rewardToken.balanceOf(address(minter));

        vm.expectEmit(address(gauge));
        emit NotifyReward({from: address(voter), amount: maxAmount});
        gauge.notifyRewardAmount({_amount: amount});

        // Redistributor received excess emissions
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBalance);
        assertEq(rewardToken.balanceOf(address(redistributor)), TOKEN_1);
        assertEq(rewardToken.balanceOf(address(voter)), 0);
        assertEq(rewardToken.balanceOf(address(gauge)), maxAmount);

        uint256 epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
        assertEq(gauge.rewardRate(), maxAmount / WEEK);
        assertEq(gauge.rewardRateByEpoch(epochStart), maxAmount / WEEK);
        assertEq(gauge.rewardsByEpoch(epochStart), maxAmount);
        assertEq(gauge.periodFinish(), block.timestamp + WEEK);
        assertEq(pool.rewardRate(), maxAmount / WEEK);
        assertEq(pool.rewardReserve(), maxAmount);
        assertEq(pool.periodFinish(), block.timestamp + WEEK);
    }

    function test_WhenTheCurrentTimestampIsLessThanPeriodFinish()
        external
        whenTheCallerIsVoter
        whenTailEmissionsHaveStarted
        whenTheAmountIsGreaterThanDefinedPercentageOfTailEmissions
    {
        // It should return excess emissions to redistributor
        // It should update the reward rate, including any existing rewards
        // It should cache the updated reward rate for this epoch
        // It should update the rewards deposited for this epoch
        // It should update the period finish timestamp
        // It should emit a {NotifyReward} event
        uint256 weeklyEmissions = (rewardToken.totalSupply() * minter.tailEmissionRate()) / MAX_BPS;
        uint256 maxEmissionRate = gaugeFactory.emissionCaps(address(gauge));
        uint256 maxAmount = maxEmissionRate * weeklyEmissions / MAX_BPS;
        uint256 amount = maxAmount + TOKEN_1;

        deal({token: address(rewardToken), to: address(voter), give: amount * 2});
        rewardToken.approve({spender: address(gauge), amount: amount * 2});

        // inital deposit of partial amount
        gauge.notifyRewardAmount({_amount: maxAmount});

        uint256 epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
        assertEq(gauge.rewardsByEpoch(epochStart), maxAmount);
        assertEq(pool.rewardRate(), maxAmount / WEEK);
        assertEq(pool.rewardReserve(), maxAmount);
        assertEq(pool.periodFinish(), block.timestamp + WEEK);

        skip(WEEK / 7 * 5);

        uint256 oldMinterBalance = rewardToken.balanceOf(address(minter));
        uint256 poolRollover = maxAmount / WEEK * (WEEK / 7 * 5);
        uint256 timeUntilNext = WEEK * 2 / 7;

        vm.expectEmit(address(gauge));
        emit NotifyReward({from: address(voter), amount: maxAmount + poolRollover});
        gauge.notifyRewardAmount({_amount: amount});

        // Redistributor received excess emissions
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBalance);
        assertEq(rewardToken.balanceOf(address(redistributor)), TOKEN_1);
        assertEq(rewardToken.balanceOf(address(voter)), amount - maxAmount);
        assertEq(rewardToken.balanceOf(address(gauge)), maxAmount * 2);

        uint256 rewardRate = ((maxAmount / WEEK) * timeUntilNext + maxAmount + poolRollover) / timeUntilNext;
        assertEq(gauge.rewardRate(), rewardRate);
        assertEq(gauge.rewardRateByEpoch(ProtocolTimeLibrary.epochStart(block.timestamp)), rewardRate);
        assertEq(gauge.rewardsByEpoch(epochStart), maxAmount * 2 + poolRollover);
        assertEq(gauge.periodFinish(), block.timestamp + WEEK / 7 * 2);
        assertEq(pool.rewardRate(), rewardRate);
        assertEq(pool.rewardReserve(), maxAmount + poolRollover + ((maxAmount / WEEK) * timeUntilNext));
        assertEq(pool.periodFinish(), block.timestamp + (WEEK / 7 * 2));
    }

    modifier whenTheAmountIsSmallerThanOrEqualToDefinedPercentageOfTailEmissions() {
        _;
    }

    function test_WhenTheCurrentTimestampIsGreaterThanOrEqualToPeriodFinish_()
        external
        whenTheCallerIsVoter
        whenTailEmissionsHaveStarted
        whenTheAmountIsSmallerThanOrEqualToDefinedPercentageOfTailEmissions
    {
        // It should update the reward rate
        // It should cache the updated reward rate for this epoch
        // It should update the rewards deposited for this epoch
        // It should update the period finish timestamp
        // It should emit a {NotifyReward} event

        uint256 amount = TOKEN_1 * 1_000;

        deal({token: address(rewardToken), to: address(voter), give: amount});
        rewardToken.approve({spender: address(gauge), amount: amount});

        assertEq(gauge.rewardToken(), address(rewardToken));

        vm.expectEmit(address(gauge));
        emit NotifyReward({from: address(voter), amount: amount});
        gauge.notifyRewardAmount({_amount: amount});

        uint256 epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
        assertEq(rewardToken.balanceOf(address(voter)), 0);
        assertEq(rewardToken.balanceOf(address(gauge)), amount);
        assertEq(gauge.rewardRate(), amount / WEEK);
        assertEq(gauge.rewardRateByEpoch(epochStart), amount / WEEK);
        assertEq(gauge.rewardsByEpoch(epochStart), amount);
        assertEq(gauge.periodFinish(), block.timestamp + WEEK);
        assertEq(pool.rewardRate(), amount / WEEK);
        assertEq(pool.rewardReserve(), amount);
        assertEq(pool.periodFinish(), block.timestamp + WEEK);
    }

    function test_WhenTheCurrentTimestampIsLessThanPeriodFinish_()
        external
        whenTheCallerIsVoter
        whenTailEmissionsHaveStarted
        whenTheAmountIsSmallerThanOrEqualToDefinedPercentageOfTailEmissions
    {
        // It should update the reward rate, including any existing rewards
        // It should cache the updated reward rate for this epoch
        // It should update the rewards deposited for this epoch
        // It should update the period finish timestamp
        // It should emit a {NotifyReward} event
        uint256 amount = TOKEN_1 * 1_000;

        deal({token: address(rewardToken), to: address(voter), give: amount * 2});
        rewardToken.approve({spender: address(gauge), amount: amount * 2});

        // inital deposit of partial amount
        gauge.notifyRewardAmount({_amount: amount});

        skip(WEEK / 7 * 5);

        uint256 timeUntilNext = WEEK * 2 / 7;

        uint256 epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
        assertEq(gauge.rewardsByEpoch(epochStart), amount);
        assertEq(pool.rewardRate(), amount / WEEK);
        assertEq(pool.rewardReserve(), amount);
        assertEq(pool.periodFinish(), block.timestamp + timeUntilNext);

        uint256 poolRollover = amount / WEEK * (WEEK / 7 * 5);

        vm.expectEmit(address(gauge));
        emit NotifyReward({from: address(voter), amount: amount + poolRollover});
        gauge.notifyRewardAmount({_amount: amount});
        assertEq(rewardToken.balanceOf(address(voter)), 0);
        assertEq(rewardToken.balanceOf(address(gauge)), amount * 2);

        uint256 rewardRate = ((amount / WEEK) * timeUntilNext + amount + poolRollover) / timeUntilNext;
        assertEq(gauge.rewardRate(), rewardRate);
        assertEq(gauge.rewardRateByEpoch(epochStart), rewardRate);
        assertEq(gauge.rewardsByEpoch(epochStart), amount * 2 + poolRollover);
        assertEq(gauge.periodFinish(), block.timestamp + WEEK / 7 * 2);
        assertEq(pool.rewardRate(), rewardRate);
        assertEq(pool.rewardReserve(), amount + poolRollover + ((amount / WEEK) * timeUntilNext));
        assertEq(pool.periodFinish(), block.timestamp + (WEEK / 7 * 2));
    }

    modifier whenTailEmissionsHaveNotStarted() {
        vm.selectFork({forkId: beforeTailFork});
        _;
    }

    modifier whenTheAmountIsGreaterThanDefinedPercentageOfWeeklyEmissions() {
        _;
    }

    function test_WhenTheCurrentTimestampIsGreaterThanOrEqualToPeriodFinish__()
        external
        whenTheCallerIsVoter
        whenTailEmissionsHaveNotStarted
        whenTheAmountIsGreaterThanDefinedPercentageOfWeeklyEmissions
    {
        // It should return excess emissions to redistributor
        // It should update the reward rate
        // It should cache the updated reward rate for this epoch
        // It should update the rewards deposited for this epoch
        // It should update the period finish timestamp
        // It should emit a {NotifyReward} event
        uint256 weeklyEmissions = (minter.weekly() * MAX_BPS) / WEEKLY_DECAY;
        uint256 maxEmissionRate = gaugeFactory.emissionCaps(address(gauge));
        uint256 maxAmount = maxEmissionRate * weeklyEmissions / MAX_BPS;
        uint256 amount = maxAmount + TOKEN_1;

        deal({token: address(rewardToken), to: address(voter), give: amount});
        rewardToken.approve({spender: address(gauge), amount: amount});

        assertEq(gauge.rewardToken(), address(rewardToken));
        uint256 oldMinterBalance = rewardToken.balanceOf(address(minter));

        vm.expectEmit(address(gauge));
        emit NotifyReward({from: address(voter), amount: maxAmount});
        gauge.notifyRewardAmount({_amount: amount});

        // Redistributor received excess emissions
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBalance);
        assertEq(rewardToken.balanceOf(address(redistributor)), TOKEN_1);
        assertEq(rewardToken.balanceOf(address(voter)), 0);
        assertEq(rewardToken.balanceOf(address(gauge)), maxAmount);

        uint256 epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
        assertEq(gauge.rewardRate(), maxAmount / WEEK);
        assertEq(gauge.rewardRateByEpoch(epochStart), maxAmount / WEEK);
        assertEq(gauge.rewardsByEpoch(epochStart), maxAmount);
        assertEq(gauge.periodFinish(), block.timestamp + WEEK);
        assertEq(pool.rewardRate(), maxAmount / WEEK);
        assertEq(pool.rewardReserve(), maxAmount);
        assertEq(pool.periodFinish(), block.timestamp + WEEK);
    }

    function test_WhenTheCurrentTimestampIsLessThanPeriodFinish__()
        external
        whenTheCallerIsVoter
        whenTailEmissionsHaveNotStarted
        whenTheAmountIsGreaterThanDefinedPercentageOfWeeklyEmissions
    {
        // It should return excess emissions to redistributor
        // It should update the reward rate, including any existing rewards
        // It should cache the updated reward rate for this epoch
        // It should update the rewards deposited for this epoch
        // It should update the period finish timestamp
        // It should emit a {NotifyReward} event
        uint256 weeklyEmissions = (minter.weekly() * MAX_BPS) / WEEKLY_DECAY;
        uint256 maxEmissionRate = gaugeFactory.emissionCaps(address(gauge));
        uint256 maxAmount = maxEmissionRate * weeklyEmissions / MAX_BPS;
        uint256 amount = maxAmount + TOKEN_1;

        deal({token: address(rewardToken), to: address(voter), give: amount * 2});
        rewardToken.approve({spender: address(gauge), amount: amount * 2});

        // inital deposit of partial amount
        gauge.notifyRewardAmount({_amount: maxAmount});

        skip(WEEK / 7 * 5);
        uint256 timeUntilNext = WEEK * 2 / 7;

        assertEq(pool.rewardRate(), maxAmount / WEEK);
        assertEq(pool.rewardReserve(), maxAmount);
        assertEq(pool.periodFinish(), block.timestamp + timeUntilNext);

        uint256 oldMinterBalance = rewardToken.balanceOf(address(minter));
        uint256 poolRollover = maxAmount / WEEK * (WEEK / 7 * 5);

        vm.expectEmit(address(gauge));
        emit NotifyReward({from: address(voter), amount: maxAmount + poolRollover});
        gauge.notifyRewardAmount({_amount: amount});

        // Redistributor received excess emissions
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBalance);
        assertEq(rewardToken.balanceOf(address(redistributor)), TOKEN_1);
        assertEq(rewardToken.balanceOf(address(voter)), amount - maxAmount);
        assertEq(rewardToken.balanceOf(address(gauge)), maxAmount * 2);

        uint256 rewardRate = ((maxAmount / WEEK) * timeUntilNext + maxAmount + poolRollover) / timeUntilNext;
        uint256 epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
        assertEq(gauge.rewardRate(), rewardRate);
        assertEq(gauge.rewardRateByEpoch(epochStart), rewardRate);
        assertEq(gauge.rewardsByEpoch(epochStart), maxAmount * 2 + poolRollover);
        assertEq(gauge.periodFinish(), block.timestamp + WEEK / 7 * 2);
        assertEq(pool.rewardRate(), rewardRate);
        assertEq(pool.rewardReserve(), maxAmount + poolRollover + ((maxAmount / WEEK) * timeUntilNext));
        assertEq(pool.periodFinish(), block.timestamp + (WEEK / 7 * 2));
    }

    modifier whenTheAmountIsSmallerThanOrEqualToDefinedPercentageOfWeeklyEmissions() {
        _;
    }

    function test_WhenTheCurrentTimestampIsGreaterThanOrEqualToPeriodFinish___()
        external
        whenTheCallerIsVoter
        whenTailEmissionsHaveNotStarted
        whenTheAmountIsSmallerThanOrEqualToDefinedPercentageOfWeeklyEmissions
    {
        // It should update the reward rate
        // It should cache the updated reward rate for this epoch
        // It should update the rewards deposited for this epoch
        // It should update the period finish timestamp
        // It should emit a {NotifyReward} event
        uint256 amount = TOKEN_1 * 1_000;
        uint256 bufferCap = amount * 2;

        deal({token: address(rewardToken), to: address(voter), give: amount});
        rewardToken.approve({spender: address(gauge), amount: amount});

        assertEq(gauge.rewardToken(), address(rewardToken));

        vm.expectEmit(address(gauge));
        emit NotifyReward({from: address(voter), amount: amount});
        gauge.notifyRewardAmount({_amount: amount});

        uint256 epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
        assertEq(rewardToken.balanceOf(address(voter)), 0);
        assertEq(rewardToken.balanceOf(address(gauge)), amount);
        assertEq(gauge.rewardRate(), amount / WEEK);
        assertEq(gauge.rewardRateByEpoch(epochStart), amount / WEEK);
        assertEq(gauge.rewardsByEpoch(epochStart), amount);
        assertEq(gauge.periodFinish(), block.timestamp + WEEK);
        assertEq(pool.rewardRate(), amount / WEEK);
        assertEq(pool.rewardReserve(), amount);
        assertEq(pool.periodFinish(), block.timestamp + WEEK);
    }

    function test_WhenTheCurrentTimestampIsLessThanPeriodFinish___()
        external
        whenTheCallerIsVoter
        whenTailEmissionsHaveNotStarted
        whenTheAmountIsSmallerThanOrEqualToDefinedPercentageOfWeeklyEmissions
    {
        // It should update the reward rate, including any existing rewards
        // It should cache the updated reward rate for this epoch
        // It should update the rewards deposited for this epoch
        // It should update the period finish timestamp
        // It should emit a {NotifyReward} event
        uint256 amount = TOKEN_1 * 1_000;

        deal({token: address(rewardToken), to: address(voter), give: amount * 2});
        rewardToken.approve({spender: address(gauge), amount: amount * 2});

        // inital deposit of partial amount
        gauge.notifyRewardAmount({_amount: amount});

        uint256 epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
        assertEq(gauge.rewardsByEpoch(epochStart), amount);
        assertEq(pool.rewardRate(), amount / WEEK);
        assertEq(pool.rewardReserve(), amount);
        assertEq(pool.periodFinish(), block.timestamp + WEEK);

        skip(WEEK / 7 * 5);

        uint256 timeUntilNext = WEEK * 2 / 7;

        assertEq(pool.rewardRate(), amount / WEEK);
        assertEq(pool.rewardReserve(), amount);
        assertEq(pool.periodFinish(), block.timestamp + timeUntilNext);

        uint256 poolRollover = amount / WEEK * (WEEK / 7 * 5);
        vm.expectEmit(address(gauge));
        emit NotifyReward({from: address(voter), amount: amount + poolRollover});
        gauge.notifyRewardAmount({_amount: amount});

        assertEq(rewardToken.balanceOf(address(voter)), 0);
        assertEq(rewardToken.balanceOf(address(gauge)), amount * 2);

        uint256 rewardRate = ((amount / WEEK) * timeUntilNext + amount + poolRollover) / timeUntilNext;
        assertEq(gauge.rewardRate(), rewardRate);
        assertEq(gauge.rewardRateByEpoch(epochStart), rewardRate);
        assertEq(gauge.rewardsByEpoch(epochStart), amount * 2 + poolRollover);
        assertEq(gauge.periodFinish(), block.timestamp + (WEEK / 7 * 2));
        assertEq(pool.rewardRate(), rewardRate);
        assertEq(pool.rewardReserve(), amount + poolRollover + ((amount / WEEK) * timeUntilNext));
        assertEq(pool.periodFinish(), block.timestamp + (WEEK / 7 * 2));
    }
}
