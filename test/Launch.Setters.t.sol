// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {LaunchTestBase} from "./LaunchTestBase.t.sol";
import {Launch} from "../src/Launch.sol";
import {LaunchGroupSettings, LaunchGroupStatus} from "../src/Types.sol";

contract LaunchTest is Test, Launch, LaunchTestBase {
    function setUp() public {
        _setUpLaunch();
    }

    /**
     * @notice Test setLaunchGroupSettings
     */
    function test_SetLaunchGroupSettings_Create() public {
        bytes32[] memory initialLaunchGroups = launch.getLaunchGroups();
        assertEq(initialLaunchGroups.length, 0);

        vm.expectEmit(true, true, true, true);
        emit LaunchGroupCreated(testLaunchGroupId);
        // Setup launch group
        LaunchGroupSettings memory settings = _setupLaunchGroup();

        // Verify launch group settings
        _verifyLaunchGroupSettings(settings);
        assertEq(launch.getLaunchGroups().length, 1);
    }

    function test_SetLaunchGroupSettings_Update() public {
        _setupLaunchGroup();

        bytes32[] memory initialLaunchGroups = launch.getLaunchGroups();
        assertEq(initialLaunchGroups.length, 1);

        vm.expectEmit(true, true, true, true);
        emit LaunchGroupUpdated(testLaunchGroupId);

        // Update launch group
        LaunchGroupSettings memory settings = _setupLaunchGroup();

        // Verify launch group settings
        _verifyLaunchGroupSettings(settings);
        assertEq(launch.getLaunchGroups(), initialLaunchGroups);
    }

    function test_RevertIf_SetLaunchGroupSettings_NotManagerRole() public {
        LaunchGroupSettings memory settings = _setupLaunchGroup();
        vm.startPrank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, operator, MANAGER_ROLE)
        );
        // Set launch group settings
        launch.setLaunchGroupSettings(testLaunchGroupId, settings);
    }

    function test_RevertIf_SetLaunchGroupSettings_InvalidRequestFinalizesAtParticipation() public {
        LaunchGroupSettings memory settings = _setupLaunchGroup();
        assertTrue(settings.status != LaunchGroupStatus.PENDING);
        assertFalse(settings.finalizesAtParticipation);
        settings.finalizesAtParticipation = true;

        vm.startPrank(manager);
        vm.expectRevert(InvalidRequest.selector);
        // Set launch group settings
        launch.setLaunchGroupSettings(testLaunchGroupId, settings);
    }

    /**
     * @notice Test setLaunchGroupStatus
     */
    function test_SetLaunchGroupStatus() public {
        _setupLaunchGroup();
        assertTrue(launch.getLaunchGroupSettings(testLaunchGroupId).status == LaunchGroupStatus.ACTIVE);

        vm.startPrank(manager);
        vm.expectEmit(true, true, true, true);
        emit LaunchGroupStatusUpdated(testLaunchGroupId, LaunchGroupStatus.PAUSED);
        // Set launch group status
        launch.setLaunchGroupStatus(testLaunchGroupId, LaunchGroupStatus.PAUSED);

        assertTrue(launch.getLaunchGroupSettings(testLaunchGroupId).status == LaunchGroupStatus.PAUSED);
    }

    function test_RevertIf_SetLaunchGroupStatus_InvalidRequestPendingStatus() public {
        _setupLaunchGroup();
        assertTrue(launch.getLaunchGroupSettings(testLaunchGroupId).status == LaunchGroupStatus.ACTIVE);

        vm.startPrank(manager);
        vm.expectRevert(InvalidRequest.selector);
        // Set launch group status
        launch.setLaunchGroupStatus(testLaunchGroupId, LaunchGroupStatus.PENDING);
    }

    /**
     * @notice Test setWithdrawalAddress
     */
    function test_SetWithdrawalAddress() public {
        assertEq(launch.withdrawalAddress(), testWithdrawalAddress);
        address newWithdrawalAddress = address(0x1234567890);

        vm.startPrank(testWithdrawalAddress);
        vm.expectEmit(true, true, true, true);
        emit WithdrawalAddressUpdated(newWithdrawalAddress);
        // Set withdrawal address
        launch.setWithdrawalAddress(newWithdrawalAddress);

        assertEq(launch.withdrawalAddress(), newWithdrawalAddress);
    }

    function test_RevertIf_SetWithdrawalAddress_NotWithdrawalRole() public {
        address newWithdrawalAddress = address(0x1234567890);
        vm.startPrank(newWithdrawalAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, newWithdrawalAddress, WITHDRAWAL_ROLE
            )
        );
        // Set withdrawal address
        launch.setWithdrawalAddress(newWithdrawalAddress);
    }

    function test_RevertIf_SetWithdrawalAddress_InvalidRequestZeroAddress() public {
        vm.startPrank(testWithdrawalAddress);
        vm.expectRevert(InvalidRequest.selector);
        // Set withdrawal address
        launch.setWithdrawalAddress(address(0));
    }

    function _verifyLaunchGroupSettings(LaunchGroupSettings memory settings) public view {
        // Verify launch group settings
        LaunchGroupSettings memory savedSettings = launch.getLaunchGroupSettings(testLaunchGroupId);
        assertEq(savedSettings.maxParticipants, settings.maxParticipants);
        assertEq(savedSettings.maxTokenAllocation, settings.maxTokenAllocation);
        assertEq(uint256(savedSettings.status), uint256(LaunchGroupStatus.ACTIVE));
        assertEq(savedSettings.startsAt, settings.startsAt);
        assertEq(savedSettings.endsAt, settings.endsAt);
    }
}
