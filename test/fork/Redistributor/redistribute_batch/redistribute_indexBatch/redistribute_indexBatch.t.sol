// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../../Redistributor.t.sol";

contract RedistributeIndexBatchIntegrationConcreteTest is RedistributorForkTest {
    using stdStorage for StdStorage;

    uint256 public startIndex;
    uint256 public endIndex;
    uint256 public epochStart;
    uint256 public totalEmissions;
    address public voterPool;
    address public voterPool2;
    address public voterGauge;
    address public voterGauge2;

    uint256 public epochStartSnapshot;

    function setUp() public virtual override {
        super.setUp();

        /// @dev Set alice as an authorized upkeep
        MockUpkeepManager(address(upkeepManager)).setUpkeep({_upkeep: users.alice, _state: true});
        uint256 length = voter.length();

        // @dev Fetch the last two gauges from the voter, excluding the 3 gauges created in the fixture
        startIndex = length - 5;
        voterPool = voter.pools(startIndex);
        voterGauge = voter.gauges({_pool: voterPool});

        voterPool2 = voter.pools(startIndex + 1);
        voterGauge2 = voter.gauges({_pool: voterPool2});

        /// @dev Exclude last gauge from end index, as it is used for the fixture
        endIndex = length - 1;

        skipToNextEpoch(0);
        epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
    }

    function _seedRedistributorAndCastVote() internal {
        /// @dev Reset redistributor balance
        deal(address(rewardToken), address(redistributor), 0);

        /// @dev Skip after distribute window and cast vote
        skipToNextEpoch(1 hours + 1);

        // Alice creates veNFT to vote
        deal(address(rewardToken), users.alice, TOKEN_1 * 1_000_000);
        vm.startPrank(users.alice);
        rewardToken.approve(address(escrow), TOKEN_1 * 1_000_000);
        uint256 tokenIdAlice = escrow.createLock(TOKEN_1 * 1_000_000, 365 days * 4);

        // Alice votes
        address[] memory pools = new address[](3);
        pools[0] = address(pool);
        pools[1] = address(voterPool);
        pools[2] = address(voterPool2);
        uint256[] memory votes = new uint256[](3);
        votes[0] = 60;
        votes[1] = 30;
        votes[2] = 20;
        voter.vote(tokenIdAlice, pools, votes);
        vm.stopPrank();

        /// @dev Skip to next epoch and deposit rewards into redistributor
        skipToNextEpoch(0);
        epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
        epochStartSnapshot = vm.snapshot();

        /// @dev Deposit rewards into redistributor from another gauge
        totalEmissions = TOKEN_1 * 10_000;
        deal(address(rewardToken), address(gauge3), totalEmissions);
        vm.startPrank(address(gauge3));
        rewardToken.approve(address(redistributor), totalEmissions);
        redistributor.deposit({_amount: totalEmissions});
        vm.stopPrank();

        skip(10 minutes);
    }

    function test_WhenTheCallerIsNotAGaugeUpkeepOrTheKeeper() external {
        // It should revert with {NotAuthorized}
        vm.prank(users.charlie);
        vm.expectRevert(bytes("NA"));
        redistributor.redistribute({_start: startIndex, _end: endIndex});
    }

    modifier whenTheCallerIsAGaugeUpkeepOrTheKeeper() {
        vm.prank(users.owner);
        redistributor.setKeeper({_keeper: users.bob});
        vm.startPrank(users.alice);
        _;
    }

    function test_WhenTheEndIsSmallerOrEqualToStart() external whenTheCallerIsAGaugeUpkeepOrTheKeeper {
        // It should revert with {Underflow}
        vm.expectRevert(bytes("UF"));
        redistributor.redistribute({_start: startIndex, _end: startIndex});

        vm.expectRevert(bytes("UF"));
        redistributor.redistribute({_start: startIndex, _end: startIndex - 1});

        vm.startPrank(users.bob);
        vm.expectRevert(bytes("UF"));
        redistributor.redistribute({_start: startIndex, _end: startIndex});

        vm.expectRevert(bytes("UF"));
        redistributor.redistribute({_start: startIndex, _end: startIndex - 1});
    }

    modifier whenTheEndIsGreaterThanStart() {
        _;
    }

    function test_WhenCalledDuringTheFirst10MinutesOfTheEpoch() external whenTheCallerIsAGaugeUpkeepOrTheKeeper {
        // It should revert with {TooSoon}
        assertLt(block.timestamp, epochStart + 10 minutes);

        vm.expectRevert(bytes("TS"));
        redistributor.redistribute({_start: startIndex, _end: endIndex});

        vm.startPrank(users.bob);
        vm.expectRevert(bytes("TS"));
        redistributor.redistribute({_start: startIndex, _end: endIndex});
    }

    modifier whenCalledAfterTheFirst10MinutesOfTheEpoch() {
        skip(10 minutes);
        _;
    }

    function test_WhenThereAreNoEmissionsToRedistribute()
        external
        whenTheCallerIsAGaugeUpkeepOrTheKeeper
        whenCalledAfterTheFirst10MinutesOfTheEpoch
    {
        // It should update the active period
        // It should skip the redistribution
        assertEq(rewardToken.balanceOf(address(redistributor)), 0);
        address[] memory gauges = new address[](3);
        gauges[0] = address(gauge);
        gauges[1] = voterGauge;
        gauges[2] = voterGauge2;

        /// @dev Ensure `notifyRewardWithoutClaim()` is not called and no tokens are transferred
        vm.expectCall(address(rewardToken), abi.encodeWithSelector(IERC20.transfer.selector), 0);
        vm.expectCall(address(gauge), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        vm.expectCall(voterGauge, abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        vm.expectCall(voterGauge2, abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        redistributor.redistribute({_start: startIndex, _end: endIndex});

        assertEq(redistributor.activePeriod(), epochStart);
        // @dev Total emissions remains unchanged
        assertEq(redistributor.totalEmissions(epochStart), 0);
    }

    modifier whenThereAreEmissionsToRedistribute() {
        _seedRedistributorAndCastVote();
        _;
    }

    function test_WhenAllGaugesAreSkipped()
        external
        whenTheCallerIsAGaugeUpkeepOrTheKeeper
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
    {
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should skip all gauges in the range

        /// @dev First gauge is skipped due to `deposit()`, to simulate emission overflow
        deal(address(rewardToken), address(gauge), TOKEN_1);
        vm.startPrank(address(gauge));
        rewardToken.approve(address(redistributor), TOKEN_1);
        redistributor.deposit({_amount: TOKEN_1});
        totalEmissions += TOKEN_1;
        vm.stopPrank();

        /// @dev Second gauge is skipped because of zero voting weight
        assertEq(voter.weights(address(pool2)), 0);

        /// @dev Third and fourth gauges are skipped because they have already received their redistributes
        vm.startPrank(users.alice);
        redistributor.redistribute({_start: startIndex, _end: startIndex + 2});
        assertTrue(redistributor.isRedistributed(epochStart, voterGauge));
        assertTrue(redistributor.isRedistributed(epochStart, voterGauge2));

        /// @dev Ensure `notifyRewardWithoutClaim()` is not called and no tokens are transferred
        vm.expectCall(address(rewardToken), abi.encodeWithSelector(IERC20.transfer.selector), 0);
        vm.expectCall(address(gauge), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        vm.expectCall(address(gauge2), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        vm.expectCall(voterGauge, abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        vm.expectCall(voterGauge2, abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        redistributor.redistribute({_start: startIndex, _end: endIndex});

        assertEq(redistributor.activePeriod(), epochStart);
        /// @dev Total emissions remains unchanged
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);

        /// @dev Second, third and fourth gauges are marked as redistributed
        assertFalse(redistributor.isRedistributed(epochStart, address(gauge)));
        assertTrue(redistributor.isRedistributed(epochStart, address(gauge2)));
        assertTrue(redistributor.isRedistributed(epochStart, voterGauge));
        assertTrue(redistributor.isRedistributed(epochStart, voterGauge2));
    }

    function test_WhenSomeGaugesReceiveRedistributes()
        external
        whenTheCallerIsAGaugeUpkeepOrTheKeeper
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
    {
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should skip the required gauges
        // It should redistribute to the remaining gauges in the range

        /// @dev Revert to Epoch Start and deposit large amount of recycled emissions, to simulate excess in first gauge
        vm.revertToState(epochStartSnapshot);
        address[] memory gauges = new address[](4);
        gauges[0] = address(gauge);
        gauges[1] = address(gauge2);
        gauges[2] = voterGauge;
        gauges[3] = voterGauge2;
        voter.distribute({_gauges: gauges});

        /// @dev Second gauge is skipped because of zero voting weight
        assertEq(voter.weights(address(pool2)), 0);

        /// @dev Deposit rewards into redistributor from another gauge
        totalEmissions = TOKEN_1 * 5_000_000;
        deal(address(rewardToken), address(gauge3), totalEmissions);
        vm.startPrank(address(gauge3));
        rewardToken.approve(address(redistributor), totalEmissions);
        redistributor.deposit({_amount: totalEmissions});
        vm.stopPrank();

        skip(10 minutes);

        uint256 prevEmissions = gauge.rewardsByEpoch(epochStart);
        uint256 maxEmissions = gaugeFactory.calculateMaxEmissions({_gauge: address(gauge)});

        // @dev Calculate total weight ratio required to exceed max emissions
        uint256 requiredEmissions = maxEmissions - prevEmissions;
        uint256 ratio = totalEmissions / requiredEmissions;
        uint256 maxWeight = voter.totalWeight() / ratio;

        assertGt(prevEmissions, 0);

        /// @dev Overwrite gauge weight to simulate emission overflow
        stdstore.target({_target: address(voter)}).sig({_sig: IVoter.weights.selector}).with_key({who: address(pool)})
            .checked_write({amt: uint256(maxWeight)});

        uint256 totalWeight = voter.totalWeight();
        uint256 gaugeEmissions1 = totalEmissions * voter.weights({_pool: address(pool)}) / totalWeight;
        uint256 gaugeEmissions2 =
            totalEmissions * voter.weights({_pool: voter.poolForGauge({_gauge: voterGauge})}) / totalWeight;
        uint256 gaugeEmissions3 =
            totalEmissions * voter.weights({_pool: voter.poolForGauge({_gauge: voterGauge2})}) / totalWeight;

        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));

        vm.prank(address(gauge));
        pool.updateRewardsGrowthGlobal();
        uint256 poolRollover = pool.rollover();

        vm.startPrank(users.alice);
        vm.expectCall(address(gauge2), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: voterGauge, amount: gaugeEmissions2});
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: voterGauge2, amount: gaugeEmissions3});
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: address(gauge), amount: maxEmissions - prevEmissions});
        redistributor.redistribute({_start: startIndex, _end: endIndex});

        /// @dev First gauge receives emissions up to the max cap
        assertEq(rewardToken.balanceOf(address(gauge)), maxEmissions);
        assertEq(gauge.rewardsByEpoch(epochStart), maxEmissions + poolRollover);
        // @dev Minter receives excess emissions from first gauge
        uint256 excessEmissions = gaugeEmissions1 + prevEmissions - maxEmissions;
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBal + excessEmissions);
        /// @dev Redistributor only transfers the gauge emission amount
        assertEq(
            rewardToken.balanceOf(address(redistributor)),
            oldRedistributorBal - (gaugeEmissions1 + gaugeEmissions2 + gaugeEmissions3)
        );

        assertTrue(redistributor.isRedistributed(epochStart, address(gauge)));
        assertTrue(redistributor.isRedistributed(epochStart, address(gauge2)));
        assertTrue(redistributor.isRedistributed(epochStart, voterGauge));
        assertTrue(redistributor.isRedistributed(epochStart, voterGauge2));
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
        assertEq(redistributor.totalWeight(epochStart), totalWeight);
    }

    function test_WhenAllGaugesReceiveRedistributes()
        external
        whenTheCallerIsAGaugeUpkeepOrTheKeeper
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
    {
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should redistribute to all gauges in the range

        // @dev Exclude last gauge, used to test skipped distributions
        endIndex -= 1;

        /// @dev Revert to Epoch Start and deposit large amount of recycled emissions, to simulate excess in first gauge
        vm.revertToState(epochStartSnapshot);
        address[] memory gauges = new address[](3);
        gauges[0] = address(gauge);
        gauges[1] = voterGauge;
        gauges[2] = voterGauge2;
        voter.distribute({_gauges: gauges});

        /// @dev Deposit rewards into redistributor from another gauge
        totalEmissions = TOKEN_1 * 5_000_000;
        deal(address(rewardToken), address(gauge3), totalEmissions);
        vm.startPrank(address(gauge3));
        rewardToken.approve(address(redistributor), totalEmissions);
        redistributor.deposit({_amount: totalEmissions});
        vm.stopPrank();

        skip(10 minutes);

        uint256 prevEmissions = gauge.rewardsByEpoch(epochStart);
        uint256 maxEmissions = gaugeFactory.calculateMaxEmissions({_gauge: address(gauge)});

        // @dev Calculate total weight ratio required to exceed max emissions
        uint256 requiredEmissions = maxEmissions - prevEmissions;
        uint256 ratio = totalEmissions / requiredEmissions;
        uint256 maxWeight = voter.totalWeight() / ratio;

        assertGt(prevEmissions, 0);

        /// @dev Overwrite gauge weight to simulate emission overflow
        stdstore.target({_target: address(voter)}).sig({_sig: IVoter.weights.selector}).with_key({who: address(pool)})
            .checked_write({amt: uint256(maxWeight)});

        uint256 totalWeight = voter.totalWeight();
        uint256 gaugeEmissions1 = totalEmissions * voter.weights({_pool: address(pool)}) / totalWeight;
        uint256 gaugeEmissions2 =
            totalEmissions * voter.weights({_pool: voter.poolForGauge({_gauge: voterGauge})}) / totalWeight;
        uint256 gaugeEmissions3 =
            totalEmissions * voter.weights({_pool: voter.poolForGauge({_gauge: voterGauge2})}) / totalWeight;

        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));

        vm.prank(address(gauge));
        pool.updateRewardsGrowthGlobal();
        uint256 poolRollover = pool.rollover();

        vm.startPrank(users.alice);
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: voterGauge, amount: gaugeEmissions2});
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: voterGauge2, amount: gaugeEmissions3});
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: address(gauge), amount: maxEmissions - prevEmissions});
        redistributor.redistribute({_start: startIndex, _end: endIndex});

        /// @dev First gauge receives emissions up to the max cap
        assertEq(rewardToken.balanceOf(address(gauge)), maxEmissions);
        assertEq(gauge.rewardsByEpoch(epochStart), maxEmissions + poolRollover);
        // @dev Minter receives excess emissions from first gauge
        uint256 excessEmissions = gaugeEmissions1 + prevEmissions - maxEmissions;
        assertEq(rewardToken.balanceOf(address(minter)), oldMinterBal + excessEmissions);
        /// @dev Redistributor only transfers the gauge emission amount
        assertEq(
            rewardToken.balanceOf(address(redistributor)),
            oldRedistributorBal - (gaugeEmissions1 + gaugeEmissions2 + gaugeEmissions3)
        );

        assertTrue(redistributor.isRedistributed(epochStart, address(gauge)));
        assertTrue(redistributor.isRedistributed(epochStart, voterGauge));
        assertTrue(redistributor.isRedistributed(epochStart, voterGauge2));
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
        assertEq(redistributor.totalWeight(epochStart), totalWeight);
    }
}
