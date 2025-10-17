// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../Redistributor.t.sol";

contract ToggleSplitIntegrationConcreteTest is RedistributorForkTest {
    address public account;

    function test_WhenTheCallerIsNotOwner() external {
        // It should revert with {"Ownable: caller is not the owner"}
        vm.prank(users.charlie);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        redistributor.toggleSplit({_account: account, _bool: true});
    }

    function test_WhenTheCallerIsTheOwner() external {
        // It shoult toggle split for the given account with the value in voting escrow
        // It should emit a {ToggleSplit} event
        vm.startPrank(users.owner);
        vm.expectEmit(address(redistributor));
        emit ToggleSplit({account: account, enabled: true});
        redistributor.toggleSplit({_account: account, _bool: true});

        assertTrue(escrow.canSplit({_account: account}));
    }
}
