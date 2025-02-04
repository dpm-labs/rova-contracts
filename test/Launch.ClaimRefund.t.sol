// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Test} from "forge-std/Test.sol";
import {LaunchTestBase, IERC20Events} from "./LaunchTestBase.t.sol";
import {Launch} from "../src/Launch.sol";
import {
    LaunchGroupSettings,
    LaunchGroupStatus,
    ParticipationRequest,
    CancelParticipationRequest,
    ClaimRefundRequest,
    ParticipationInfo
} from "../src/Types.sol";

contract LaunchClaimRefundTest is Test, Launch, LaunchTestBase, IERC20Events {
    LaunchGroupSettings public settings;

    function setUp() public {
        _setUpLaunch();

        // Setup initial participation
        settings = _setupLaunchGroup();
        ParticipationRequest memory request = _createParticipationRequest();
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        currency.approve(address(launch), _getCurrencyAmount(request.currencyBps, request.tokenAmount));
        launch.participate(request, signature);

        vm.stopPrank();

        // Complete the launch group
        vm.startPrank(manager);
        launch.setLaunchGroupStatus(testLaunchGroupId, LaunchGroupStatus.COMPLETED);
        vm.stopPrank();
    }

    function test_ClaimRefund() public {
        // Claim refund
        ClaimRefundRequest memory refundRequest = _createClaimRefundRequest();
        bytes memory refundSignature = _signRequest(abi.encode(refundRequest));

        ParticipationInfo memory initialInfo = launch.getParticipationInfo(testLaunchParticipationId);
        uint256 initialCurrencyBalance = currency.balanceOf(user1);
        uint256 initialTotalCurrencyDeposits = launch.getDepositsByCurrency(testLaunchGroupId, initialInfo.currency);

        vm.startPrank(user1);

        // Verify RefundClaimed and Transfer events
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(launch), user1, initialInfo.currencyAmount);
        vm.expectEmit(true, true, true, true);
        emit RefundClaimed(
            testLaunchGroupId,
            testLaunchParticipationId,
            testUserId,
            user1,
            initialInfo.currencyAmount,
            initialInfo.currency
        );

        // Claim refund
        launch.claimRefund(refundRequest, refundSignature);

        // Verify refund
        ParticipationInfo memory newInfo = launch.getParticipationInfo(testLaunchParticipationId);
        assertEq(newInfo.tokenAmount, 0);
        assertEq(newInfo.currencyAmount, 0);
        assertEq(currency.balanceOf(user1), initialCurrencyBalance + initialInfo.currencyAmount);

        // Verify total deposits
        uint256 totalCurrencyDeposits = launch.getDepositsByCurrency(testLaunchGroupId, initialInfo.currency);
        assertEq(totalCurrencyDeposits, initialTotalCurrencyDeposits - initialInfo.currencyAmount);

        vm.stopPrank();
    }

    function test_RevertIf_ClaimRefund_LaunchPaused() public {
        vm.startPrank(admin.addr);
        launch.pause();
        vm.stopPrank();

        // Prepare claim refund request
        ClaimRefundRequest memory request = _createClaimRefundRequest();
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        // Claim refund
        launch.claimRefund(request, signature);
    }

    function test_RevertIf_ClaimRefund_InvalidLaunchGroupStatus() public {
        // Update launch group status
        vm.startPrank(manager);
        launch.setLaunchGroupStatus(testLaunchGroupId, LaunchGroupStatus.PAUSED);
        vm.stopPrank();

        // Prepare claim refund request
        ClaimRefundRequest memory request = _createClaimRefundRequest();
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidLaunchGroupStatus.selector,
                testLaunchGroupId,
                LaunchGroupStatus.COMPLETED,
                LaunchGroupStatus.PAUSED
            )
        );
        // Claim refund
        launch.claimRefund(request, signature);
    }

    function test_RevertIf_ClaimRefund_InvalidRequestLaunchId() public {
        // Prepare claim refund request
        ClaimRefundRequest memory request = _createClaimRefundRequest();
        request.launchId = "invalidLaunchId";
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(InvalidRequest.selector);
        // Claim refund
        launch.claimRefund(request, signature);
    }

    function test_RevertIf_ClaimRefund_InvalidRequestChainId() public {
        // Prepare claim refund request
        ClaimRefundRequest memory request = _createClaimRefundRequest();
        request.chainId = 1;
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(InvalidRequest.selector);
        // Claim refund
        launch.claimRefund(request, signature);
    }

    function test_RevertIf_ClaimRefund_InvalidRequestUserAddress() public {
        // Prepare claim refund request
        ClaimRefundRequest memory request = _createClaimRefundRequest();
        request.userAddress = address(0);
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(InvalidRequest.selector);
        // Claim refund
        launch.claimRefund(request, signature);
    }

    function test_RevertIf_ClaimRefund_InvalidRequestUserId() public {
        // Prepare claim refund request
        ClaimRefundRequest memory request = _createClaimRefundRequest();
        request.userId = "invalidUserId";
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(InvalidRequestUserId.selector, testUserId, request.userId));
        // Claim refund
        launch.claimRefund(request, signature);
    }

    function test_RevertIf_ClaimRefund_ExpiredRequest() public {
        // Prepare claim refund request
        ClaimRefundRequest memory request = _createClaimRefundRequest();
        request.requestExpiresAt = 0;
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(ExpiredRequest.selector, request.requestExpiresAt, block.timestamp));
        // Claim refund
        launch.claimRefund(request, signature);
    }

    function test_RevertIf_ClaimRefund_InvalidSignatureSigner() public {
        // Prepare claim refund request
        ClaimRefundRequest memory request = _createClaimRefundRequest();
        bytes memory signature = _signRequestWithSigner(abi.encode(request), 0x1234567890);

        vm.startPrank(user1);
        vm.expectRevert(InvalidSignature.selector);
        // Claim refund
        launch.claimRefund(request, signature);
    }

    function test_RevertIf_ClaimRefund_InvalidSignatureInput() public {
        // Prepare claim refund request
        ClaimRefundRequest memory request = _createClaimRefundRequest();
        request.requestExpiresAt = block.timestamp + 4 hours;
        bytes memory signature = _signRequest(abi.encode(_createClaimRefundRequest()));

        vm.startPrank(user1);
        vm.expectRevert(InvalidSignature.selector);
        // Claim refund
        launch.claimRefund(request, signature);
    }

    function test_RevertIf_ClaimRefund_InvalidRefundRequestIsFinalized() public {
        // Update launch group status
        vm.startPrank(manager);
        launch.setLaunchGroupStatus(testLaunchGroupId, LaunchGroupStatus.ACTIVE);
        vm.stopPrank();

        // Set as winner
        vm.startPrank(operator);
        bytes32[] memory participationIds = new bytes32[](1);
        participationIds[0] = testLaunchParticipationId;
        launch.finalizeWinners(testLaunchGroupId, participationIds);
        vm.stopPrank();

        // Update launch group status
        vm.startPrank(manager);
        launch.setLaunchGroupStatus(testLaunchGroupId, LaunchGroupStatus.COMPLETED);
        vm.stopPrank();

        // Prepare claim refund request
        ClaimRefundRequest memory request = _createClaimRefundRequest();
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(InvalidRefundRequest.selector, testLaunchParticipationId));
        // Claim refund
        launch.claimRefund(request, signature);
    }

    function test_RevertIf_ClaimRefund_InvalidRefundRequest() public {
        // Update launch group status
        vm.startPrank(manager);
        launch.setLaunchGroupStatus(testLaunchGroupId, LaunchGroupStatus.ACTIVE);
        vm.stopPrank();

        // Cancel participation
        vm.startPrank(user1);
        CancelParticipationRequest memory cancelRequest = _createCancelParticipationRequest();
        bytes memory cancelSignature = _signRequest(abi.encode(cancelRequest));
        launch.cancelParticipation(cancelRequest, cancelSignature);
        vm.stopPrank();

        // Update launch group status
        vm.startPrank(manager);
        launch.setLaunchGroupStatus(testLaunchGroupId, LaunchGroupStatus.COMPLETED);
        vm.stopPrank();

        // Prepare claim refund request
        ClaimRefundRequest memory request = _createClaimRefundRequest();
        bytes memory signature = _signRequest(abi.encode(request));

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(InvalidRefundRequest.selector, testLaunchParticipationId));
        // Claim refund
        launch.claimRefund(request, signature);
    }

    function _createClaimRefundRequest() internal view returns (ClaimRefundRequest memory) {
        return ClaimRefundRequest({
            chainId: block.chainid,
            launchId: testLaunchId,
            launchGroupId: testLaunchGroupId,
            launchParticipationId: testLaunchParticipationId,
            userId: testUserId,
            userAddress: user1,
            requestExpiresAt: block.timestamp + 1 hours
        });
    }
}
