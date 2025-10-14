// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../CLGaugeFactory.t.sol";

contract CalculateMaxEmissionsIntegrationConcreteTest is CLGaugeFactoryForkTest {
    modifier whenActivePeriodIsNotEqualToActivePeriodInMinter() {
        assertNotEq(gaugeFactory.activePeriod(), minter.activePeriod());
        _;
    }

    function test_WhenActivePeriodIsNotEqualToActivePeriodInMinter() external {
        // It should calculate tail emissions
        // It should cache the current minter active period
        // It should cache the weekly emissions for this epoch
        // It should return max amount based on weekly emissions and gauge emission cap
        uint256 weeklyEmissions = (rewardToken.totalSupply() * minter.tailEmissionRate()) / MAX_BPS;
        uint256 maxEmissionRate = gaugeFactory.emissionCaps(address(gauge));
        uint256 expectedMaxAmount = maxEmissionRate * weeklyEmissions / MAX_BPS;

        uint256 maxAmount = gaugeFactory.calculateMaxEmissions({_gauge: address(gauge)});

        assertEq(gaugeFactory.activePeriod(), minter.activePeriod());
        assertEq(gaugeFactory.weeklyEmissions(), weeklyEmissions);
        assertEq(maxAmount, expectedMaxAmount);
    }

    function test_WhenActivePeriodIsEqualToActivePeriodInMinter() external {
        // It should return max amount based on cached weekly emissions and gauge emission cap
        gaugeFactory.calculateMaxEmissions({_gauge: address(gauge)});
        assertEq(gaugeFactory.activePeriod(), minter.activePeriod());

        uint256 weeklyEmissions = gaugeFactory.weeklyEmissions();
        uint256 maxEmissionRate = gaugeFactory.emissionCaps(address(gauge));
        uint256 expectedMaxAmount = maxEmissionRate * weeklyEmissions / MAX_BPS;

        uint256 maxAmount = gaugeFactory.calculateMaxEmissions({_gauge: address(gauge)});

        assertEq(gaugeFactory.activePeriod(), minter.activePeriod());
        assertEq(gaugeFactory.weeklyEmissions(), weeklyEmissions);
        assertEq(maxAmount, expectedMaxAmount);
    }
}
