// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.22;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {LaunchTestBase} from "./LaunchTestBase.t.sol";
import {Launch} from "../src/Launch.sol";
import {LaunchGroupSettings, LaunchGroupStatus, CurrencyConfig} from "../src/Types.sol";

contract LaunchTest is Test, Launch, LaunchTestBase {
    function setUp() public {
        _setUpLaunch();
    }

    /**
     * @notice Test setLaunchGroupSettings
     */
    function test_SetLaunchGroupSettings() public {
        LaunchGroupSettings memory settings = _setupLaunchGroup();
        settings.maxParticipants = 100;
        settings.maxParticipationsPerUser = 10;
        settings.maxTokenAllocation = 1000000;
        settings.startsAt = block.timestamp + 1 days;
        settings.endsAt = block.timestamp + 2 days;

        bytes32[] memory initialLaunchGroups = launch.getLaunchGroups();
        assertEq(initialLaunchGroups.length, 1);

        vm.expectEmit(true, true, true, true);
        emit LaunchGroupUpdated(testLaunchGroupId);

        // Update launch group
        _updateLaunchGroupSettings(settings);

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

    function test_RevertIf_SetLaunchGroupSettings_InvalidRequestLaunchGroupNotExists() public {
        LaunchGroupSettings memory settings = _setupLaunchGroup();

        vm.startPrank(manager);
        vm.expectRevert(InvalidRequest.selector);
        // Setup launch group
        launch.setLaunchGroupSettings("differentLaunchGroupId", settings);
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

    /**
     * @notice Test setLaunchGroupCurrency
     */
    function test_SetLaunchGroupCurrency() public {
        _setupLaunchGroup();
        CurrencyConfig memory currencyConfig = launch.getLaunchGroupCurrencyConfig(testLaunchGroupId, address(currency));
        currencyConfig.tokenPriceBps = 10000;
        currencyConfig.minAmount = 1;
        currencyConfig.maxAmount = 2;
        vm.expectEmit(true, true, true, true);
        emit LaunchGroupCurrencyUpdated(testLaunchGroupId, address(currency));
        vm.startPrank(manager);
        // Set launch group currency
        launch.setLaunchGroupCurrency(testLaunchGroupId, address(currency), currencyConfig);

        CurrencyConfig memory updatedConfig = launch.getLaunchGroupCurrencyConfig(testLaunchGroupId, address(currency));
        assertEq(updatedConfig.tokenPriceBps, currencyConfig.tokenPriceBps);
        assertEq(updatedConfig.minAmount, currencyConfig.minAmount);
        assertEq(updatedConfig.maxAmount, currencyConfig.maxAmount);
    }

    function test_RevertIf_SetLaunchGroupCurrency_InvalidRequestCurrencyConfigZeroTokenPriceBps() public {
        _setupLaunchGroup();
        CurrencyConfig memory currencyConfig = launch.getLaunchGroupCurrencyConfig(testLaunchGroupId, address(currency));
        currencyConfig.tokenPriceBps = 0;
        vm.startPrank(manager);
        vm.expectRevert(InvalidRequest.selector);
        // Set launch group currency
        launch.setLaunchGroupCurrency(testLaunchGroupId, address(currency), currencyConfig);
    }

    function test_RevertIf_SetLaunchGroupCurrency_InvalidRequestCurrencyConfigZeroInvalidAmountRange() public {
        _setupLaunchGroup();
        CurrencyConfig memory currencyConfig = launch.getLaunchGroupCurrencyConfig(testLaunchGroupId, address(currency));
        currencyConfig.minAmount = 100;
        currencyConfig.maxAmount = 1;
        vm.startPrank(manager);
        vm.expectRevert(InvalidRequest.selector);
        // Set launch group currency
        launch.setLaunchGroupCurrency(testLaunchGroupId, address(currency), currencyConfig);
    }

    function test_RevertIf_SetLaunchGroupCurrency_NotManagerRole() public {
        _setupLaunchGroup();
        CurrencyConfig memory currencyConfig = launch.getLaunchGroupCurrencyConfig(testLaunchGroupId, address(currency));
        vm.startPrank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, operator, MANAGER_ROLE)
        );
        // Set launch group currency
        launch.setLaunchGroupCurrency(testLaunchGroupId, address(currency), currencyConfig);
    }

    /**
     * @notice Test toggleLaunchGroupCurrencyEnabled
     */
    function test_ToggleLaunchGroupCurrencyEnabled() public {
        _setupLaunchGroup();
        bool prevConfigIsEnabled = launch.getLaunchGroupCurrencyConfig(testLaunchGroupId, address(currency)).isEnabled;
        vm.expectEmit(true, true, true, true);
        emit LaunchGroupCurrencyUpdated(testLaunchGroupId, address(currency));
        vm.startPrank(manager);
        // Toggle launch group currency
        launch.toggleLaunchGroupCurrencyEnabled(testLaunchGroupId, address(currency), !prevConfigIsEnabled);

        assertEq(
            launch.getLaunchGroupCurrencyConfig(testLaunchGroupId, address(currency)).isEnabled, !prevConfigIsEnabled
        );
    }

    function test_RevertIf_ToggleLaunchGroupCurrencyEnabled_NotManagerRole() public {
        _setupLaunchGroup();
        vm.startPrank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, operator, MANAGER_ROLE)
        );
        // Toggle launch group currency
        launch.toggleLaunchGroupCurrencyEnabled(testLaunchGroupId, address(currency), false);
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
