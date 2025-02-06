// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.22;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Test} from "forge-std/Test.sol";
import {LaunchTestBase} from "./LaunchTestBase.t.sol";
import {Launch} from "../src/Launch.sol";
import {
    LaunchGroupSettings,
    LaunchGroupStatus,
    ParticipationRequest,
    ParticipationInfo,
    CurrencyConfig
} from "../src/Types.sol";

contract LaunchParticipateTest is Test, Launch, LaunchTestBase {
    function setUp() public {
        _setUpLaunch();
    }

    function test_Participate_DoesNotFinalizeAtParticipation() public {
        // Setup launch group
        _setupLaunchGroup();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        uint256 currencyAmount = _getCurrencyAmount(request.launchGroupId, request.currency, request.tokenAmount);
        currency.approve(address(launch), currencyAmount);

        // Expect ParticipationRegistered event
        vm.expectEmit();
        emit ParticipationRegistered(
            request.launchGroupId, request.launchParticipationId, testUserId, user1, currencyAmount, address(currency)
        );

        // Participate
        launch.participate(request, signature);

        // Verify participation
        ParticipationInfo memory info = launch.getParticipationInfo(request.launchParticipationId);
        assertEq(info.userAddress, user1);
        assertEq(info.userId, testUserId);
        assertEq(info.tokenAmount, request.tokenAmount);
        assertEq(info.currencyAmount, currencyAmount);
        assertEq(info.currency, address(currency));
        assertEq(info.isFinalized, false);

        // Verify total deposits
        assertEq(launch.getDepositsByCurrency(testLaunchGroupId, address(currency)), currencyAmount);

        // Verify total unique participants by launch group
        assertEq(launch.getNumUniqueParticipantsByLaunchGroup(testLaunchGroupId), 1);

        // Verify total participations by user for the launch group
        assertEq(launch.getNumParticipationsByUser(testLaunchGroupId, testUserId), 1);

        // Verify total tokens sold
        assertEq(launch.getTokensSoldByLaunchGroup(testLaunchGroupId), 0);

        // Verify total withdrawable amount
        assertEq(launch.getWithdrawableAmountByCurrency(address(currency)), 0);

        vm.stopPrank();
    }

    function test_Participate_FinalizesAtParticipation() public {
        // Setup new launch group
        bytes32 launchGroupId = bytes32(uint256(1));
        LaunchGroupSettings memory settings = _setupLaunchGroupWithStatus(launchGroupId, LaunchGroupStatus.PENDING);
        settings.finalizesAtParticipation = true;
        vm.startPrank(manager);
        launch.setLaunchGroupSettings(launchGroupId, settings);
        launch.setLaunchGroupStatus(launchGroupId, LaunchGroupStatus.ACTIVE);
        vm.stopPrank();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        request.launchGroupId = launchGroupId;
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        uint256 currencyAmount = _getCurrencyAmount(request.launchGroupId, request.currency, request.tokenAmount);
        currency.approve(address(launch), currencyAmount);

        // Expect ParticipationRegistered event
        vm.expectEmit();
        emit ParticipationRegistered(
            request.launchGroupId, request.launchParticipationId, testUserId, user1, currencyAmount, address(currency)
        );

        // Participate
        launch.participate(request, signature);

        // Verify participation
        ParticipationInfo memory info = launch.getParticipationInfo(request.launchParticipationId);
        assertEq(info.userAddress, user1);
        assertEq(info.userId, testUserId);
        assertEq(info.tokenAmount, request.tokenAmount);
        assertEq(info.currencyAmount, currencyAmount);
        assertEq(info.currency, address(currency));
        assertEq(info.isFinalized, true);

        // Verify total deposits
        assertEq(launch.getDepositsByCurrency(request.launchGroupId, address(currency)), currencyAmount);

        // Verify total unique participants by launch group
        assertEq(launch.getNumUniqueParticipantsByLaunchGroup(request.launchGroupId), 1);

        // Verify total participations by user for the launch group
        assertEq(launch.getNumParticipationsByUser(request.launchGroupId, testUserId), 1);

        // Verify total tokens sold
        assertEq(launch.getTokensSoldByLaunchGroup(request.launchGroupId), request.tokenAmount);

        // Verify total withdrawable amount
        assertEq(launch.getWithdrawableAmountByCurrency(address(currency)), currencyAmount);

        vm.stopPrank();
    }

    function test_Participate_MultipleParticipations() public {
        // Setup new launch group
        bytes32 launchGroupId = bytes32(uint256(1));
        LaunchGroupSettings memory settings = _setupLaunchGroupWithStatus(launchGroupId, LaunchGroupStatus.PENDING);
        settings.finalizesAtParticipation = true;
        vm.startPrank(manager);
        launch.setLaunchGroupSettings(launchGroupId, settings);
        launch.setLaunchGroupStatus(launchGroupId, LaunchGroupStatus.ACTIVE);
        vm.stopPrank();

        // Multiple participations from same user
        bytes32[] memory participationIds = new bytes32[](2);
        participationIds[0] = "participationId1";
        participationIds[1] = "participationId2";
        ParticipationRequest memory request = _createParticipationRequest();
        request.launchGroupId = launchGroupId;
        uint256 currencyAmount = _getCurrencyAmount(request.launchGroupId, request.currency, request.tokenAmount);

        for (uint256 i = 0; i < participationIds.length; i++) {
            // Prepare participation request
            request.launchParticipationId = participationIds[i];
            bytes memory signature = _signRequest(abi.encode(request));

            vm.startPrank(user1);
            currency.approve(address(launch), currencyAmount);

            // Expect ParticipationRegistered event
            vm.expectEmit();
            emit ParticipationRegistered(
                request.launchGroupId,
                request.launchParticipationId,
                testUserId,
                user1,
                currencyAmount,
                address(currency)
            );

            // Participate
            launch.participate(request, signature);

            // Verify participation
            ParticipationInfo memory info = launch.getParticipationInfo(request.launchParticipationId);
            assertEq(info.userAddress, user1);
            assertEq(info.userId, testUserId);
            assertEq(info.tokenAmount, request.tokenAmount);
            assertEq(info.currencyAmount, currencyAmount);
            assertEq(info.currency, address(currency));
            assertEq(info.isFinalized, true);
        }

        // Verify total deposits
        assertEq(launch.getDepositsByCurrency(request.launchGroupId, address(currency)), currencyAmount * 2);

        // Verify total unique participants by launch group
        assertEq(launch.getNumUniqueParticipantsByLaunchGroup(request.launchGroupId), 1);

        // Verify total participations by user for the launch group
        assertEq(launch.getNumParticipationsByUser(request.launchGroupId, testUserId), 2);

        // Verify total tokens sold
        assertEq(launch.getTokensSoldByLaunchGroup(request.launchGroupId), request.tokenAmount * 2);

        // Verify total withdrawable amount
        assertEq(launch.getWithdrawableAmountByCurrency(address(currency)), currencyAmount * 2);

        vm.stopPrank();
    }

    function test_RevertIf_Participate_LaunchPaused() public {
        // Setup launch group
        _setupLaunchGroup();
        vm.startPrank(admin.addr);
        launch.pause();
        vm.stopPrank();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_InvalidLaunchGroupStatus() public {
        _setupLaunchGroup();
        // Update launch group status
        vm.startPrank(manager);
        launch.setLaunchGroupStatus(testLaunchGroupId, LaunchGroupStatus.COMPLETED);
        vm.stopPrank();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidLaunchGroupStatus.selector,
                testLaunchGroupId,
                LaunchGroupStatus.ACTIVE,
                LaunchGroupStatus.COMPLETED
            )
        );
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_InvalidRequestLaunchId() public {
        // Setup launch group
        _setupLaunchGroup();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        request.launchId = "invalidLaunchId";
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(InvalidRequest.selector);
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_InvalidRequestChainId() public {
        // Setup launch group
        _setupLaunchGroup();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        request.chainId = 1;
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(InvalidRequest.selector);
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_InvalidRequestStartsAtTimestamp() public {
        // Setup launch group
        LaunchGroupSettings memory settings = _setupLaunchGroup();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        vm.warp(settings.startsAt - 1);
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(InvalidRequest.selector);
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_InvalidRequestEndsAtTimestamp() public {
        // Setup launch group
        LaunchGroupSettings memory settings = _setupLaunchGroup();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        vm.warp(settings.endsAt + 1 hours);
        request.requestExpiresAt = settings.endsAt + 2 hours;
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(InvalidRequest.selector);
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_InvalidRequestUserAddress() public {
        // Setup launch group
        _setupLaunchGroup();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        request.userAddress = address(0);
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(InvalidRequest.selector);
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_ExpiredRequest() public {
        // Setup launch group
        _setupLaunchGroup();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        request.requestExpiresAt = 0;
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(ExpiredRequest.selector, request.requestExpiresAt, block.timestamp));
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_InvalidSignatureSigner() public {
        // Setup launch group
        _setupLaunchGroup();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        bytes memory signature = _signRequestWithSigner(abi.encode(request), 0x1234567890);

        vm.startPrank(user1);
        vm.expectRevert(InvalidSignature.selector);
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_InvalidSignatureInput() public {
        // Setup launch group
        _setupLaunchGroup();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        request.tokenAmount -= 1;
        bytes memory signature = _signRequest(abi.encode(_createParticipationRequest()));

        vm.startPrank(user1);
        vm.expectRevert(InvalidSignature.selector);
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_InvalidRequestCurrencyNotRegistered() public {
        // Setup launch group
        _setupLaunchGroup();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        request.currency = address(20);
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(InvalidRequest.selector);
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_InvalidRequestCurrencyNotEnabled() public {
        // Setup launch group
        _setupLaunchGroup();

        // Register new currency
        vm.startPrank(manager);
        launch.setLaunchGroupCurrency(
            testLaunchGroupId,
            address(20),
            CurrencyConfig({tokenPriceBps: 10000, minAmount: 1, maxAmount: 2, isEnabled: false})
        );
        vm.stopPrank();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        request.currency = address(20);
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(InvalidRequest.selector);
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_InvalidRequestCurrencyAmountBelowMin() public {
        // Setup launch group
        _setupLaunchGroup();
        CurrencyConfig memory currencyConfig = launch.getLaunchGroupCurrencyConfig(testLaunchGroupId, address(currency));

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        request.tokenAmount = currencyConfig.minAmount - 1;
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidCurrencyAmount.selector, testLaunchGroupId, address(currency), request.tokenAmount
            )
        );
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_InvalidRequestCurrencyAmountAboveMax() public {
        // Setup launch group
        _setupLaunchGroup();
        CurrencyConfig memory currencyConfig = launch.getLaunchGroupCurrencyConfig(testLaunchGroupId, address(currency));

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        request.tokenAmount = currencyConfig.maxAmount + 1;
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidCurrencyAmount.selector, testLaunchGroupId, address(currency), request.tokenAmount
            )
        );
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_ParticipationAlreadyExists() public {
        // Setup launch group
        _setupLaunchGroup();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        currency.approve(
            address(launch), _getCurrencyAmount(request.launchGroupId, request.currency, request.tokenAmount)
        );
        // First participation
        launch.participate(request, signature);

        vm.expectRevert(abi.encodeWithSelector(ParticipationAlreadyExists.selector, request.launchParticipationId));
        // Second participation
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_MaxUserParticipationsReached() public {
        // Setup launch group
        LaunchGroupSettings memory settings = _setupLaunchGroup();
        vm.startPrank(manager);
        settings.maxParticipationsPerUser = 1;
        launch.setLaunchGroupSettings(testLaunchGroupId, settings);
        vm.stopPrank();

        // Prepare participation requests
        ParticipationRequest memory firstRequest = _createParticipationRequest();
        bytes memory firstSignature = _signRequest(abi.encode(firstRequest));
        ParticipationRequest memory secondRequest = _createParticipationRequest();
        secondRequest.launchParticipationId = "differentLaunchParticipationId";
        bytes memory secondSignature = _signRequest(abi.encode(secondRequest));

        vm.startPrank(user1);
        // First participation
        currency.approve(
            address(launch),
            _getCurrencyAmount(firstRequest.launchGroupId, firstRequest.currency, firstRequest.tokenAmount)
        );
        launch.participate(firstRequest, firstSignature);

        // Second participation
        currency.approve(
            address(launch),
            _getCurrencyAmount(secondRequest.launchGroupId, secondRequest.currency, secondRequest.tokenAmount)
        );
        vm.expectRevert(abi.encodeWithSelector(MaxUserParticipationsReached.selector, testLaunchGroupId, testUserId));
        launch.participate(secondRequest, secondSignature);
    }

    function test_RevertIf_Participate_MaxParticipantsReached() public {
        // Setup launch group
        LaunchGroupSettings memory settings = _setupLaunchGroup();
        vm.startPrank(manager);
        settings.maxParticipants = 1;
        launch.setLaunchGroupSettings(testLaunchGroupId, settings);
        vm.stopPrank();

        // Prepare participation requests
        ParticipationRequest memory firstRequest = _createParticipationRequest();
        bytes memory firstSignature = _signRequest(abi.encode(firstRequest));

        // First user participant
        vm.startPrank(user1);
        currency.approve(
            address(launch),
            _getCurrencyAmount(firstRequest.launchGroupId, firstRequest.currency, firstRequest.tokenAmount)
        );
        launch.participate(firstRequest, firstSignature);
        vm.stopPrank();

        // Second user participant
        vm.startPrank(user2);
        ParticipationRequest memory secondRequest = _createParticipationRequest();
        secondRequest.userId = "differentUserId";
        secondRequest.userAddress = user2;
        secondRequest.launchParticipationId = "differentLaunchParticipationId";
        bytes memory secondSignature = _signRequest(abi.encode(secondRequest));
        vm.expectRevert(abi.encodeWithSelector(MaxParticipantsReached.selector, testLaunchGroupId));
        launch.participate(secondRequest, secondSignature);
    }

    function test_RevertIf_Participate_MaxTokenAllocationReached() public {
        // Setup new launch group
        bytes32 launchGroupId = bytes32(uint256(1));
        LaunchGroupSettings memory settings = _setupLaunchGroupWithStatus(launchGroupId, LaunchGroupStatus.PENDING);
        settings.finalizesAtParticipation = true;
        settings.maxTokenAllocation = 500 * 10 ** launch.tokenDecimals();
        vm.startPrank(manager);
        launch.setLaunchGroupSettings(launchGroupId, settings);
        launch.setLaunchGroupStatus(launchGroupId, LaunchGroupStatus.ACTIVE);
        vm.stopPrank();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        request.launchGroupId = launchGroupId;
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(MaxTokenAllocationReached.selector, launchGroupId));
        // Participate
        launch.participate(request, signature);
    }

    function test_RevertIf_Participate_ERC20InsufficientBalance() public {
        // Setup launch group
        _setupLaunchGroup();

        // Prepare participation request
        ParticipationRequest memory request = _createParticipationRequest();
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        currency.transfer(user2, currency.balanceOf(user1));
        uint256 currencyAmount = _getCurrencyAmount(request.launchGroupId, request.currency, request.tokenAmount);
        currency.approve(address(launch), currencyAmount);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user1, 0, currencyAmount)
        );
        // Participate
        launch.participate(request, signature);
    }
}
