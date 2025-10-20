// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../Redistributor.t.sol";

contract SetKeeperIntegrationConcreteTest is RedistributorForkTest {
    address newKeeper;

    function setUp() public override {
        super.setUp();
        newKeeper = address(0x1234);
    }

    function test_WhenTheCallerIsNotOwner() external {
        // It should revert with {"Ownable: caller is not the owner"}
        vm.prank(users.charlie);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        redistributor.setKeeper({_keeper: newKeeper});
    }

    modifier whenTheCallerIsTheOwner() {
        vm.startPrank(users.owner);
        _;
    }

    function test_WhenTheKeeperIsZeroAddress() external whenTheCallerIsTheOwner {
        // It should revert with {ZeroAddress}
        vm.expectRevert(bytes("ZA"));
        redistributor.setKeeper({_keeper: address(0)});
    }

    function test_WhenTheKeeperIsNotZeroAddress() external whenTheCallerIsTheOwner {
        // It should set the new keeper
        // It should emit a {SetKeeper} event
        vm.expectEmit(address(redistributor));
        emit SetKeeper({keeper: newKeeper});
        redistributor.setKeeper({_keeper: newKeeper});

        assertEq(redistributor.keeper(), newKeeper);
    }
}
