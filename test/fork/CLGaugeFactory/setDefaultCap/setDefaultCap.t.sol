// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../CLGaugeFactory.t.sol";

contract SetDefaultCapIntegrationConcreteTest is CLGaugeFactoryForkTest {
    function test_WhenCallerIsNotTheEmissionAdmin() external {
        // It should revert with {NotAuthorized}
        vm.prank(users.charlie);
        vm.expectRevert(bytes("NA"));
        gaugeFactory.setDefaultCap({_defaultCap: 1000});
    }

    modifier whenCallerIsTheEmissionAdmin() {
        vm.startPrank(gaugeFactory.emissionAdmin());
        _;
    }

    function test_WhenDefaultCapIsZero() external whenCallerIsTheEmissionAdmin {
        // It should revert with {ZeroDefaultCap}
        vm.expectRevert(bytes("ZDC"));
        gaugeFactory.setDefaultCap({_defaultCap: 0});
    }

    modifier whenDefaultCapIsNotZero() {
        vm.expectEmit(address(gaugeFactory));
        emit SetDefaultCap({_newDefaultCap: 1000});
        gaugeFactory.setDefaultCap({_defaultCap: 1000});
        _;
    }

    function test_WhenDefaultCapIsGreaterThanMaxBps() external whenCallerIsTheEmissionAdmin whenDefaultCapIsNotZero {
        // It should revert with {MaxCap}
        vm.expectRevert(bytes("MC"));
        gaugeFactory.setDefaultCap({_defaultCap: 10_001});
    }

    function test_WhenDefaultCapIsLessOrEqualToMaxBps() external whenCallerIsTheEmissionAdmin whenDefaultCapIsNotZero {
        // It should set the new default cap for gauges
        // It should emit a {DefaultCapSet} event
        vm.expectEmit(address(gaugeFactory));
        emit SetDefaultCap({_newDefaultCap: 1000});
        gaugeFactory.setDefaultCap({_defaultCap: 1000});

        assertEq(gaugeFactory.defaultCap(), 1000);
    }
}
