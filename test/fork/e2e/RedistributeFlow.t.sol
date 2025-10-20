pragma solidity ^0.7.6;
pragma abicoder v2;

import "../BaseForkFixture.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "../../../contracts/periphery/libraries/TransferHelper.sol";

contract RedistributeFlowTest is BaseForkFixture {
    using stdStorage for StdStorage;

    CLPool public pool1;
    CLPool public pool2;
    CLPool public pool3;
    CLGauge public gauge1;
    CLGauge public gauge2;
    CLGauge public gauge3;
    address[] public gauges;
    uint256 EMISSION = TOKEN_1;
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    uint256 tokenId1;
    uint256 tokenId2;
    uint256 tokenId3;
    address veTokenHolder = makeAddr("veTokenHolder");
    uint256 tokenIdVe;
    address[] pools;
    uint256[] weights;
    uint256 epochStart;

    function setUp() public override {
        // after tail - current scenario
        blockNumber = 36820718;
        super.setUp();

        pool1 = CLPool(
            poolFactory.createPool({
                tokenA: address(weth),
                tokenB: address(dai),
                tickSpacing: TICK_SPACING_60,
                sqrtPriceX96: encodePriceSqrt(1, 1)
            })
        );
        pool2 = CLPool(
            poolFactory.createPool({
                tokenA: address(weth),
                tokenB: address(rewardToken),
                tickSpacing: TICK_SPACING_60,
                sqrtPriceX96: encodePriceSqrt(1, 1)
            })
        );
        pool3 = CLPool(
            poolFactory.createPool({
                tokenA: address(dai),
                tokenB: address(rewardToken),
                tickSpacing: TICK_SPACING_60,
                sqrtPriceX96: encodePriceSqrt(1, 1)
            })
        );

        gauge1 = CLGauge(payable(voter.createGauge({_poolFactory: address(poolFactory), _pool: address(pool1)})));
        gauge2 = CLGauge(payable(voter.createGauge({_poolFactory: address(poolFactory), _pool: address(pool2)})));
        gauge3 = CLGauge(payable(voter.createGauge({_poolFactory: address(poolFactory), _pool: address(pool3)})));

        gauges = new address[](3);
        gauges[0] = address(gauge1);
        gauges[1] = address(gauge2);
        gauges[2] = address(gauge3);

        // set default emission cap (100 basis points = 1% of weekly emissions)
        vm.startPrank(users.owner);
        gaugeFactory.setDefaultCap({_defaultCap: 100});
        vm.stopPrank();

        // Create staked LPers for each gauge
        tokenId1 = createStakedLper({
            user: user1,
            gauge: gauge1,
            token0: pool1.token0(),
            token1: pool1.token1(),
            amountToken0: TOKEN_1 * 1_000,
            amountToken1: TOKEN_1 * 1_000_000
        });

        tokenId2 = createStakedLper({
            user: user2,
            gauge: gauge2,
            token0: pool2.token0(),
            token1: pool2.token1(),
            amountToken0: TOKEN_1 * 1_000,
            amountToken1: TOKEN_1 * 1_000_000
        });

        tokenId3 = createStakedLper({
            user: user3,
            gauge: gauge3,
            token0: pool3.token0(),
            token1: pool3.token1(),
            amountToken0: TOKEN_1 * 1_000_000,
            amountToken1: TOKEN_1 * 1_000_000
        });

        // Make veTokenHolder the only voter for simplicity
        stdstore.target({_target: address(voter)}).sig({_sig: IVoter.totalWeight.selector}).checked_write({
            amt: uint256(0)
        });

        // Create veNFT for veTokenHolder and vote
        deal(address(rewardToken), veTokenHolder, TOKEN_1 * 10_000);
        vm.startPrank(veTokenHolder);
        rewardToken.approve(address(escrow), TOKEN_1 * 10_000);
        tokenIdVe = escrow.createLock(TOKEN_1 * 10_000, 365 days * 4);

        // Skip to voting window
        skipToNextEpoch(1 hours + 1);

        pools = new address[](3);
        pools[0] = address(pool1);
        pools[1] = address(pool2);
        pools[2] = address(pool3);
        weights = new uint256[](3);
        weights[0] = 50;
        weights[1] = 30;
        weights[2] = 20;

        voter.vote(tokenIdVe, pools, weights);
        vm.stopPrank();

        vm.prank(users.owner);
        redistributor.setKeeper({_keeper: users.bob});
    }

    function createStakedLper(
        address user,
        CLGauge gauge,
        address token0,
        address token1,
        uint256 amountToken0,
        uint256 amountToken1
    ) internal returns (uint256 tokenId) {
        // Create a custom NFTManagerCallee for this specific token pair
        NFTManagerCallee customCallee = new NFTManagerCallee(token0, token1, address(nft));

        vm.startPrank(user);
        deal(token0, user, amountToken0);
        IERC20(token0).approve(address(customCallee), amountToken0);
        deal(token1, user, amountToken1);
        IERC20(token1).approve(address(customCallee), amountToken1);
        tokenId = customCallee.mintNewFullRangePositionForUserWith60TickSpacing(amountToken0, amountToken1, user);
        nft.approve(address(gauge), tokenId);
        gauge.deposit(tokenId);
        vm.stopPrank();

        assertEq(IERC20(token0).balanceOf(user), 0);
        assertEq(IERC20(token1).balanceOf(user), 0);
    }

    function claimAndCheckBalances(uint256 expectedClaimed1, uint256 expectedClaimed2, uint256 expectedClaimed3)
        internal
    {
        uint256 balanceBefore = rewardToken.balanceOf(user1);
        vm.prank(user1);
        gauge1.getReward(tokenId1);
        uint256 claimed1 = rewardToken.balanceOf(user1) - balanceBefore;
        assertApproxEqAbs(claimed1, expectedClaimed1, 600000);
        assertLe(rewardToken.balanceOf(address(gauge1)), 600000);

        balanceBefore = rewardToken.balanceOf(user2);
        vm.prank(user2);
        gauge2.getReward(tokenId2);
        uint256 claimed2 = rewardToken.balanceOf(user2) - balanceBefore;
        assertApproxEqAbs(claimed2, expectedClaimed2, 600000);
        assertLe(rewardToken.balanceOf(address(gauge2)), 600000);

        balanceBefore = rewardToken.balanceOf(user3);
        vm.prank(user3);
        gauge3.getReward(tokenId3);
        uint256 claimed3 = rewardToken.balanceOf(user3) - balanceBefore;
        assertApproxEqAbs(claimed3, expectedClaimed3, 600000);
        assertLe(rewardToken.balanceOf(address(gauge3)), 600000);
    }

    function testFork_RedistributeFlow() public {
        // Epoch 1
        // Normal emissions, no overflow
        skipToNextEpoch(0);
        epochStart = block.timestamp;

        uint256 emissionAmount = TOKEN_1;
        deal(address(rewardToken), address(voter), emissionAmount * 3);

        vm.startPrank(address(voter));
        rewardToken.approve(address(gauge1), emissionAmount);
        rewardToken.approve(address(gauge2), emissionAmount);
        rewardToken.approve(address(gauge3), emissionAmount);

        gauge1.notifyRewardAmount(emissionAmount);
        gauge2.notifyRewardAmount(emissionAmount);
        gauge3.notifyRewardAmount(emissionAmount);
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(address(redistributor)), 0);
        assertEq(rewardToken.balanceOf(address(gauge1)), emissionAmount);
        assertEq(rewardToken.balanceOf(address(gauge2)), emissionAmount);
        assertEq(rewardToken.balanceOf(address(gauge3)), emissionAmount);
        assertEq(gauge1.rewardsByEpoch(epochStart), emissionAmount);
        assertEq(gauge2.rewardsByEpoch(epochStart), emissionAmount);
        assertEq(gauge3.rewardsByEpoch(epochStart), emissionAmount);

        skip(1 hours + 1);
        vm.prank(veTokenHolder);
        voter.vote(tokenIdVe, pools, weights);

        skipToNextEpoch(0);
        claimAndCheckBalances(emissionAmount, emissionAmount, emissionAmount);
        // Epoch 2
        // gauge1 overflows
        // gauge2 and gauge3 do not overflow
        epochStart = block.timestamp;

        uint256 balanceGauge1 = rewardToken.balanceOf(address(gauge1));
        uint256 balanceGauge2 = rewardToken.balanceOf(address(gauge2));
        uint256 balanceGauge3 = rewardToken.balanceOf(address(gauge3));

        // gauges have the same max cap (no need to fetch all)
        uint256 maxEmissions = gaugeFactory.calculateMaxEmissions(address(gauge1));

        uint256 overflow = TOKEN_1;
        uint256 emission1 = maxEmissions + overflow; // overflow by TOKEN_1
        uint256 emission2 = maxEmissions - overflow; // TOKEN_1 under max
        uint256 emission3 = maxEmissions - overflow; // TOKEN_1 under max

        deal(address(rewardToken), address(voter), emission1 + emission2 + emission3);

        vm.startPrank(address(voter));
        rewardToken.approve(address(gauge1), emission1);
        rewardToken.approve(address(gauge2), emission2);
        rewardToken.approve(address(gauge3), emission3);

        // Notify and verify each gauge receives correct amount
        // gauge1 will overflow, only maxEmissions should stay in gauge
        gauge1.notifyRewardAmount(emission1);
        gauge2.notifyRewardAmount(emission2);
        gauge3.notifyRewardAmount(emission3);
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(address(redistributor)), overflow);
        assertApproxEqAbs(rewardToken.balanceOf(address(gauge1)) - balanceGauge1, maxEmissions, 1);
        assertApproxEqAbs(rewardToken.balanceOf(address(gauge2)) - balanceGauge2, emission2, 1);
        assertApproxEqAbs(rewardToken.balanceOf(address(gauge3)) - balanceGauge3, emission3, 1);
        assertEq(gauge1.rewardsByEpoch(epochStart), maxEmissions);
        assertEq(gauge2.rewardsByEpoch(epochStart), emission2);
        assertEq(gauge3.rewardsByEpoch(epochStart), emission3);

        // Redistributor should distribute overflow pro-rata to gauge2 and gauge3
        // gauge2 has 30% votes (60% of redistribute), gauge3 has 20% votes (40% of redistribute)
        uint256 expectedRedistributed2 = overflow * 60 / 100;
        uint256 expectedRedistributed3 = overflow * 40 / 100;
        balanceGauge1 = rewardToken.balanceOf(address(gauge1));
        balanceGauge2 = rewardToken.balanceOf(address(gauge2));
        balanceGauge3 = rewardToken.balanceOf(address(gauge3));

        skip(10 minutes);
        vm.prank(users.bob);
        redistributor.redistribute(gauges);

        assertLe(rewardToken.balanceOf(address(redistributor)), 1);
        assertApproxEqAbs(rewardToken.balanceOf(address(gauge1)), balanceGauge1, 1);
        assertApproxEqAbs(rewardToken.balanceOf(address(gauge2)) - balanceGauge2, expectedRedistributed2, 1);
        assertApproxEqAbs(rewardToken.balanceOf(address(gauge3)) - balanceGauge3, expectedRedistributed3, 1);
        assertEq(gauge1.rewardsByEpoch(epochStart), maxEmissions);
        assertEq(gauge2.rewardsByEpoch(epochStart), emission2 + expectedRedistributed2);
        assertApproxEqAbs(gauge3.rewardsByEpoch(epochStart), emission3 + expectedRedistributed3, 1);

        skipToNextEpoch(1 hours + 1);
        vm.prank(veTokenHolder);
        voter.vote(tokenIdVe, pools, weights);

        skipToNextEpoch(0);
        // gauge1 gets capped amount, gauge2 and gauge3 get normal + pro-rata overflow
        claimAndCheckBalances(maxEmissions, emission2 + expectedRedistributed2, emission3 + expectedRedistributed3);
        // Epoch 3
        // gauge1 overflows by large amount
        // gauge2 hits cap during redistribution (excess goes to minter)
        // gauge3 receives its full share
        epochStart = block.timestamp;

        balanceGauge1 = rewardToken.balanceOf(address(gauge1));
        balanceGauge2 = rewardToken.balanceOf(address(gauge2));
        balanceGauge3 = rewardToken.balanceOf(address(gauge3));

        // gauge1 overflow by 10 * TOKEN_1
        // 6 TOKEN_1 to gauge2, 4 TOKEN_1 to gauge3
        overflow = TOKEN_1 * 10;
        emission1 = maxEmissions + overflow;
        emission2 = maxEmissions - TOKEN_1 * 2; // gauge2 only has room for 2 more TOKEN_1
        emission3 = maxEmissions - TOKEN_1 * 4;

        deal(address(rewardToken), address(voter), emission1 + emission2 + emission3);

        vm.startPrank(address(voter));
        rewardToken.approve(address(gauge1), emission1);
        rewardToken.approve(address(gauge2), emission2);
        rewardToken.approve(address(gauge3), emission3);

        gauge1.notifyRewardAmount(emission1);
        gauge2.notifyRewardAmount(emission2);
        gauge3.notifyRewardAmount(emission3);
        vm.stopPrank();

        // Verify overflow from gauge1 went to redistributor
        assertApproxEqAbs(rewardToken.balanceOf(address(redistributor)), overflow, 1);
        assertApproxEqAbs(rewardToken.balanceOf(address(gauge1)) - balanceGauge1, maxEmissions, 1);
        assertApproxEqAbs(rewardToken.balanceOf(address(gauge2)) - balanceGauge2, emission2, 1);
        assertApproxEqAbs(rewardToken.balanceOf(address(gauge3)) - balanceGauge3, emission3, 1);
        assertEq(gauge1.rewardsByEpoch(epochStart), maxEmissions);
        assertEq(gauge2.rewardsByEpoch(epochStart), emission2);
        assertEq(gauge3.rewardsByEpoch(epochStart), emission3);

        // Calculate expected redistribution
        // gauge2 gets 60% of overflow = 6 TOKEN_1, but can only accept 2 TOKEN_1
        // gauge3 gets 40% of overflow = 4 TOKEN_1
        expectedRedistributed2 = overflow * 60 / 100; // 6 TOKEN_1
        expectedRedistributed3 = overflow * 40 / 100; // 4 TOKEN_1
        uint256 gauge2Excess = 4 * TOKEN_1;

        uint256 minterBalanceBefore = rewardToken.balanceOf(address(minter));
        balanceGauge1 = rewardToken.balanceOf(address(gauge1));
        balanceGauge2 = rewardToken.balanceOf(address(gauge2));
        balanceGauge3 = rewardToken.balanceOf(address(gauge3));

        skip(10 minutes);
        vm.prank(users.bob);
        redistributor.redistribute(gauges);

        // Redistributor should be empty
        assertLe(rewardToken.balanceOf(address(redistributor)), 1);

        assertApproxEqAbs(rewardToken.balanceOf(address(gauge1)), balanceGauge1, 1);
        assertApproxEqAbs(
            rewardToken.balanceOf(address(gauge2)) - balanceGauge2, expectedRedistributed2 - gauge2Excess, 1
        );
        assertApproxEqAbs(rewardToken.balanceOf(address(gauge3)) - balanceGauge3, expectedRedistributed3, 1);
        assertApproxEqAbs(rewardToken.balanceOf(address(minter)) - minterBalanceBefore, gauge2Excess, 1);
        assertEq(gauge1.rewardsByEpoch(epochStart), maxEmissions);
        assertEq(gauge2.rewardsByEpoch(epochStart), emission2 + expectedRedistributed2 - gauge2Excess);
        assertEq(gauge3.rewardsByEpoch(epochStart), emission3 + expectedRedistributed3);
    }
}
