// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../CLGaugeFactory.t.sol";

contract SetEmissionCapIntegrationConcreteTest is CLGaugeFactoryForkTest {
    function test_WhenCallerIsNotTheEmissionAdmin() external {
        // It should revert with {NotAuthorized}
        vm.prank(users.charlie);
        vm.expectRevert(bytes("NA"));
        gaugeFactory.setEmissionCap({_gauge: address(0), _emissionCap: 1000});
    }

    modifier whenCallerIsTheEmissionAdmin() {
        vm.startPrank(gaugeFactory.emissionAdmin());
        _;
    }

    function test_WhenGaugeIsTheZeroAddress() external whenCallerIsTheEmissionAdmin {
        // It should revert with {ZeroAddress}
        vm.expectRevert(bytes("ZA"));
        gaugeFactory.setEmissionCap({_gauge: address(0), _emissionCap: 1000});
    }

    modifier whenGaugeIsNotTheZeroAddress() {
        _;
    }

    function test_WhenEmissionCapIsGreaterThanMaxBps()
        external
        whenCallerIsTheEmissionAdmin
        whenGaugeIsNotTheZeroAddress
    {
        // It should revert with {MaxCap}
        vm.expectRevert(bytes("MC"));
        gaugeFactory.setEmissionCap({_gauge: address(gauge), _emissionCap: 10_001});
    }

    function test_WhenEmissionCapIsLessOrEqualToMaxBps()
        external
        whenCallerIsTheEmissionAdmin
        whenGaugeIsNotTheZeroAddress
    {
        // It should set the new emission cap for the gauge
        // It should emit a {EmissionCapSet} event
        assertEq(gaugeFactory.emissionCaps(address(gauge)), 100);

        vm.expectEmit(address(gaugeFactory));
        emit SetEmissionCap({_gauge: address(gauge), _newEmissionCap: 1000});
        gaugeFactory.setEmissionCap({_gauge: address(gauge), _emissionCap: 1000});

        assertEq(gaugeFactory.emissionCaps(address(gauge)), 1000);
    }
}
