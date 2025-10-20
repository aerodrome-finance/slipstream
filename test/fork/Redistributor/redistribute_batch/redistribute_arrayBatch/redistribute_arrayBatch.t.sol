// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../../Redistributor.t.sol";

contract RedistributeArrayBatchIntegrationConcreteTest is RedistributorForkTest {
    using stdStorage for StdStorage;

    uint256 public epochStart;
    uint256 public totalEmissions;
    address public v2Gauge;
    address public legacyCLGauge;

    uint256 public epochStartSnapshot;

    function setUp() public virtual override {
        super.setUp();

        /// @dev Set alice as an authorized upkeep
        MockUpkeepManager(address(upkeepManager)).setUpkeep({_upkeep: users.alice, _state: true});
        v2Gauge = 0x4F09bAb2f0E15e2A078A227FE1537665F55b8360; // USDC/AERO gauge
        legacyCLGauge = 0xF33a96b5932D9E9B9A0eDA447AbD8C9d48d2e0c8; // WETH/USDC legacy gauge

        skipToNextEpoch(0);
        epochStart = ProtocolTimeLibrary.epochStart(block.timestamp);
    }

    function _seedRedistributorAndCastVote() internal {
        /// @dev Reset redistributor balance
        deal(address(rewardToken), address(redistributor), 0);

        /// @dev Skip after distribute window and cast vote
        skipToNextEpoch(1 hours + 1);

        // Alice creates veNFT to vote
        deal(address(rewardToken), users.alice, TOKEN_1 * 1_000);
        vm.startPrank(users.alice);
        rewardToken.approve(address(escrow), TOKEN_1 * 1_000);
        uint256 tokenIdAlice = escrow.createLock(TOKEN_1 * 1_000, 365 days * 4);

        // Alice votes
        address[] memory pools = new address[](1);
        pools[0] = address(pool);
        uint256[] memory votes = new uint256[](1);
        votes[0] = 100;
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
        address[] memory gauges = new address[](0);

        vm.prank(users.charlie);
        vm.expectRevert(bytes("NA"));
        redistributor.redistribute({_gauges: gauges});
    }

    modifier whenTheCallerIsAGaugeUpkeepOrTheKeeper() {
        vm.prank(users.owner);
        redistributor.setKeeper({_keeper: users.bob});
        vm.startPrank(users.alice);
        _;
    }

    function test_WhenCalledDuringTheFirst10MinutesOfTheEpoch() external whenTheCallerIsAGaugeUpkeepOrTheKeeper {
        // It should revert with {TooSoon}
        assertLt(block.timestamp, epochStart + 10 minutes);
        address[] memory gauges = new address[](0);

        vm.expectRevert(bytes("TS"));
        redistributor.redistribute({_gauges: gauges});

        vm.startPrank(users.bob);
        vm.expectRevert(bytes("TS"));
        redistributor.redistribute({_gauges: gauges});
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
        gauges[1] = legacyCLGauge;
        gauges[2] = v2Gauge;

        /// @dev Ensure `notifyRewardWithoutClaim()` is not called and no tokens are transferred
        vm.expectCall(address(rewardToken), abi.encodeWithSelector(IERC20.transfer.selector), 0);
        vm.expectCall(address(gauge), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        vm.expectCall(legacyCLGauge, abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        vm.expectCall(v2Gauge, abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        redistributor.redistribute({_gauges: gauges});

        assertEq(redistributor.activePeriod(), epochStart);
        // @dev Total emissions remains unchanged
        assertEq(redistributor.totalEmissions(epochStart), 0);
    }

    modifier whenThereAreEmissionsToRedistribute() {
        _seedRedistributorAndCastVote();
        _;
    }

    function test_WhenOneOfTheAddressesInTheArrayIsNotAGauge()
        external
        whenTheCallerIsAGaugeUpkeepOrTheKeeper
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenThereAreEmissionsToRedistribute
    {
        // It should revert with {NotGauge}
        address[] memory gauges = new address[](4);
        gauges[0] = address(gauge);
        gauges[1] = legacyCLGauge;
        gauges[2] = v2Gauge;
        gauges[3] = users.charlie;

        vm.startPrank(users.alice);
        vm.expectRevert(bytes("NG"));
        redistributor.redistribute({_gauges: gauges});
    }

    modifier whenAllAddressesInTheArrayAreValidGauges() {
        _;
    }

    function test_WhenAllGaugesAreSkipped()
        external
        whenTheCallerIsAGaugeUpkeepOrTheKeeper
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenAllAddressesInTheArrayAreValidGauges
        whenThereAreEmissionsToRedistribute
    {
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should skip all gauges

        /// @dev First gauge is skipped due to `deposit()`, to simulate emission overflow
        deal(address(rewardToken), address(gauge), TOKEN_1);
        vm.startPrank(address(gauge));
        rewardToken.approve(address(redistributor), TOKEN_1);
        redistributor.deposit({_amount: TOKEN_1});
        totalEmissions += TOKEN_1;
        vm.stopPrank();

        /// @dev Second gauge is skipped because of zero voting weight
        assertEq(voter.weights(address(pool2)), 0);

        /// @dev Third gauge is skipped because it has already received its redistribute
        vm.startPrank(users.alice);
        address[] memory gauges = new address[](1);
        gauges[0] = legacyCLGauge;
        redistributor.redistribute({_gauges: gauges});

        gauges = new address[](3);
        gauges[0] = address(gauge);
        gauges[1] = address(gauge2);
        gauges[2] = legacyCLGauge;

        /// @dev Ensure `notifyRewardWithoutClaim()` is not called and no tokens are transferred
        vm.expectCall(address(rewardToken), abi.encodeWithSelector(IERC20.transfer.selector), 0);
        vm.expectCall(address(gauge), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        vm.expectCall(address(gauge2), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        vm.expectCall(legacyCLGauge, abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        redistributor.redistribute({_gauges: gauges});

        assertEq(redistributor.activePeriod(), epochStart);
        /// @dev Total emissions remains unchanged
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);

        /// @dev Second and third gauges are marked as redistributed
        assertFalse(redistributor.isRedistributed(epochStart, address(gauge)));
        assertTrue(redistributor.isRedistributed(epochStart, address(gauge2)));
        assertTrue(redistributor.isRedistributed(epochStart, legacyCLGauge));
    }

    function test_WhenSomeGaugesReceiveRedistributes()
        external
        whenTheCallerIsAGaugeUpkeepOrTheKeeper
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenAllAddressesInTheArrayAreValidGauges
        whenThereAreEmissionsToRedistribute
    {
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should skip the required gauges
        // It should redistribute to the remaining gauges

        /// @dev Revert to Epoch Start and deposit large amount of recycled emissions, to simulate excess in first gauge
        vm.revertToState(epochStartSnapshot);
        address[] memory gauges = new address[](4);
        gauges[0] = address(gauge);
        gauges[1] = address(gauge2);
        gauges[2] = legacyCLGauge;
        gauges[3] = v2Gauge;
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
            totalEmissions * voter.weights({_pool: voter.poolForGauge({_gauge: legacyCLGauge})}) / totalWeight;
        uint256 gaugeEmissions3 =
            totalEmissions * voter.weights({_pool: voter.poolForGauge({_gauge: v2Gauge})}) / totalWeight;

        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));

        vm.prank(address(gauge));
        pool.updateRewardsGrowthGlobal();
        uint256 poolRollover = pool.rollover();

        vm.startPrank(users.alice);
        vm.expectCall(address(gauge2), abi.encodeWithSelector(CLGauge.notifyRewardWithoutClaim.selector), 0);
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: address(gauge), amount: maxEmissions - prevEmissions});
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: legacyCLGauge, amount: gaugeEmissions2});
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: v2Gauge, amount: gaugeEmissions3});
        redistributor.redistribute({_gauges: gauges});

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
        assertTrue(redistributor.isRedistributed(epochStart, legacyCLGauge));
        assertTrue(redistributor.isRedistributed(epochStart, v2Gauge));
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
        assertEq(redistributor.totalWeight(epochStart), totalWeight);
    }

    function test_WhenAllGaugesReceiveRedistributes()
        external
        whenTheCallerIsAGaugeUpkeepOrTheKeeper
        whenCalledAfterTheFirst10MinutesOfTheEpoch
        whenAllAddressesInTheArrayAreValidGauges
        whenThereAreEmissionsToRedistribute
    {
        // It should update the total emissions for the epoch
        // It should update the active period
        // It should redistribute to all gauges

        /// @dev Revert to Epoch Start and deposit large amount of recycled emissions, to simulate excess in first gauge
        vm.revertToState(epochStartSnapshot);
        address[] memory gauges = new address[](3);
        gauges[0] = address(gauge);
        gauges[1] = legacyCLGauge;
        gauges[2] = v2Gauge;
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
            totalEmissions * voter.weights({_pool: voter.poolForGauge({_gauge: legacyCLGauge})}) / totalWeight;
        uint256 gaugeEmissions3 =
            totalEmissions * voter.weights({_pool: voter.poolForGauge({_gauge: v2Gauge})}) / totalWeight;

        uint256 oldMinterBal = rewardToken.balanceOf(address(minter));
        uint256 oldRedistributorBal = rewardToken.balanceOf(address(redistributor));

        vm.prank(address(gauge));
        pool.updateRewardsGrowthGlobal();
        uint256 poolRollover = pool.rollover();

        vm.startPrank(users.alice);
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: address(gauge), amount: maxEmissions - prevEmissions});
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: legacyCLGauge, amount: gaugeEmissions2});
        vm.expectEmit(address(redistributor));
        emit Redistributed({sender: users.alice, gauge: v2Gauge, amount: gaugeEmissions3});
        redistributor.redistribute({_gauges: gauges});

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
        assertTrue(redistributor.isRedistributed(epochStart, legacyCLGauge));
        assertTrue(redistributor.isRedistributed(epochStart, v2Gauge));
        assertEq(redistributor.totalEmissions(epochStart), totalEmissions);
        assertEq(redistributor.activePeriod(), epochStart);
        assertEq(redistributor.totalWeight(epochStart), totalWeight);
    }
}
