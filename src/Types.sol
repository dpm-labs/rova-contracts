// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.22;

/// @notice The status of a launch group.
enum LaunchGroupStatus {
    PENDING,
    ACTIVE,
    PAUSED,
    COMPLETED
}

/// @notice Contains the settings of a launch group.
/// @param finalizesAtParticipation If true, launch group sales will finalize at the participation.
/// @param startsAt The timestamp at which the launch group participation starts.
/// @param endsAt The timestamp at which the launch group participation ends.
/// @param maxParticipants The maximum number of participants in the launch group.
/// @param maxParticipationsPerUser The maximum number of participations per user.
/// @param maxTokenAllocation The maximum token allocation for the launch group.
/// @param status The status of the launch group.
struct LaunchGroupSettings {
    bool finalizesAtParticipation;
    uint256 startsAt;
    uint256 endsAt;
    uint256 maxParticipants;
    uint256 maxParticipationsPerUser;
    uint256 maxTokenAllocation;
    LaunchGroupStatus status;
}

/// @notice Contains the information of a participation.
/// @param userAddress The address of the user.
/// @param userId The unique identifier of the user.
/// @param tokenAmount The amount of tokens the user wants to purchase.
/// @param currencyAmount The amount of currency the user should pay.
/// @param currency The currency of the participation.
/// @param isFinalized Whether the participation is finalized.
struct ParticipationInfo {
    address userAddress;
    bytes32 userId;
    uint256 tokenAmount;
    uint256 currencyAmount;
    address currency;
    bool isFinalized;
}

/// @notice Contains the request to participate in a launch group.
/// @param chainId The chain ID for this launch.
/// @param launchId The unique identifier of the launch.
/// @param launchGroupId The unique identifier of the launch group.
/// @param launchParticipationId The unique identifier of the participation.
/// @param userId The unique identifier of the user.
/// @param userAddress The address of the user.
/// @param tokenAmount The amount of tokens the user wants to purchase.
/// @param currencyBps The currency basis points of the participation.
/// @param currency The currency of the participation.
/// @param requestExpiresAt The timestamp at which the request expires.
struct ParticipationRequest {
    uint256 chainId;
    bytes32 launchId;
    bytes32 launchGroupId;
    bytes32 launchParticipationId;
    bytes32 userId;
    address userAddress;
    uint256 tokenAmount;
    uint256 currencyBps;
    address currency;
    uint256 requestExpiresAt;
}

/// @notice Contains the request to update a participation in a launch group.
/// @param chainId The chain ID for this launch.
/// @param launchId The unique identifier of the launch.
/// @param launchGroupId The unique identifier of the launch group.
/// @param prevLaunchParticipationId The unique identifier of the previous participation.
/// @param newLaunchParticipationId The unique identifier of the new participation.
/// @param userId The unique identifier of the user.
/// @param userAddress The address of the user.
/// @param tokenAmount The amount of tokens the user wants to purchase.
/// @param currencyBps The currency basis points of the participation.
/// @param currency The currency of the participation.
/// @param requestExpiresAt The timestamp at which the request expires.
struct UpdateParticipationRequest {
    uint256 chainId;
    bytes32 launchId;
    bytes32 launchGroupId;
    bytes32 prevLaunchParticipationId;
    bytes32 newLaunchParticipationId;
    bytes32 userId;
    address userAddress;
    uint256 tokenAmount;
    uint256 currencyBps;
    address currency;
    uint256 requestExpiresAt;
}

/// @notice Contains the request to cancel a participation in a launch group.
/// @param chainId The chain ID for this launch.
/// @param launchId The unique identifier of the launch.
/// @param launchGroupId The unique identifier of the launch group.
/// @param launchParticipationId The unique identifier of the participation.
/// @param userId The unique identifier of the user.
/// @param userAddress The address of the user.
/// @param requestExpiresAt The timestamp at which the request expires.
struct CancelParticipationRequest {
    uint256 chainId;
    bytes32 launchId;
    bytes32 launchGroupId;
    bytes32 launchParticipationId;
    bytes32 userId;
    address userAddress;
    uint256 requestExpiresAt;
}

/// @notice Contains the request to claim a refund for a participation in a launch group.
/// @param chainId The chain ID for this launch.
/// @param launchId The unique identifier of the launch.
/// @param launchGroupId The unique identifier of the launch group.
/// @param launchParticipationId The unique identifier of the participation.
/// @param userId The unique identifier of the user.
/// @param userAddress The address of the user.
/// @param requestExpiresAt The timestamp at which the request expires.
struct ClaimRefundRequest {
    uint256 chainId;
    bytes32 launchId;
    bytes32 launchGroupId;
    bytes32 launchParticipationId;
    bytes32 userId;
    address userAddress;
    uint256 requestExpiresAt;
}
