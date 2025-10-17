// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../Redistributor.t.sol";

contract SetArtProxyIntegrationConcreteTest is RedistributorForkTest {
    address public proxy = address(1);

    function test_WhenTheCallerIsNotOwner() external {
        // It should revert with {"Ownable: caller is not the owner"}
        vm.prank(users.charlie);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        redistributor.setArtProxy({_proxy: proxy});
    }

    function test_WhenTheCallerIsTheOwner() external {
        // It should set the new art proxy in the voting escrow
        // It should emit a {SetArtProxy} event
        vm.startPrank(users.owner);
        vm.expectEmit(address(redistributor));
        emit SetArtProxy(proxy);
        redistributor.setArtProxy({_proxy: proxy});

        assertEq(escrow.artProxy(), proxy);
    }
}
