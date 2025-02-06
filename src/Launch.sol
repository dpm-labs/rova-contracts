// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
    CancelParticipationRequest,
    ClaimRefundRequest,
    CurrencyConfig,
    LaunchGroupSettings,
    LaunchGroupStatus,
    ParticipationInfo,
    ParticipationRequest,
    UpdateParticipationRequest
} from "./Types.sol";

/**
 * @title Launch
 * @notice Main launch contract that manages state and launch groups
 */
contract Launch is
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice Manager role for managing launch group settings
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Withdrawal role for managing withdrawal address
    bytes32 public constant WITHDRAWAL_ROLE = keccak256("WITHDRAWAL_ROLE");

    /// @notice Operator role for performing automated operations like selecting winners
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Signer role for generating signatures to be verified by the contract
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    /// @notice Address for withdrawing funds
    address public withdrawalAddress;

    /// @notice Launch identifiers
    bytes32 public launchId;

    /// @notice Decimals for the launch token
    /// @dev This is used to calculate currency payment amount conversions
    uint8 public tokenDecimals;

    /// @notice Launch group identifiers
    EnumerableSet.Bytes32Set internal _launchGroups;

    /// @notice Launch group settings
    /// @dev This maps (launchGroupId => LaunchGroupSettings)
    mapping(bytes32 => LaunchGroupSettings) public launchGroupSettings;

    /// @notice Participation information for each launch group
    /// @dev This maps (launchGroupId => launchParticipationId => ParticipationInfo)
    mapping(bytes32 => ParticipationInfo) public launchGroupParticipations;

    /// @notice Launch group currencies to the currency config
    mapping(bytes32 => mapping(address => CurrencyConfig)) internal _launchGroupCurrencies;

    /// @notice Total tokens sold for each launch group
    /// @dev This maps (launchGroupId => amount) and is only updated for finalized participations
    EnumerableMap.Bytes32ToUintMap internal _tokensSoldByLaunchGroup;

    /// @notice List of participants for each launch group
    /// @dev This maps (launchGroupId => userId => number of participations by this user)
    mapping(bytes32 => EnumerableMap.Bytes32ToUintMap) internal _userParticipationsByLaunchGroup;

    /// @notice Total deposits for each launch group by currency
    /// @dev This maps (launchGroupId => payment currency => amount)
    /// @dev The amounts do not reflect amount that can be withdrawn since it contains unfinalized launchGroupParticipations
    /// @dev This is not updated when funds are withdrawn, so it can be used to refund amount paid by users for finalized + unrefunded participations
    /// @dev Once all refunds are done, it should reflect total deposits for finalized participations
    mapping(bytes32 => EnumerableMap.AddressToUintMap) internal _currencyDepositsByLaunchGroup;

    /// @notice Total finalized deposits for each launch group by currency
    /// @dev This maps (payment currency => amount) and keeps track of the total amount that can be withdrawn to the withdrawal address
    EnumerableMap.AddressToUintMap internal _withdrawableAmountByCurrency;

    error InvalidRequest();
    error InvalidCurrency(bytes32 launchGroupId, address currency);
    error InvalidCurrencyAmount(bytes32 launchGroupId, address currency, uint256 currencyAmount);
    error InvalidSignature();
    error InvalidBalances(uint256 expectedBalance, uint256 actualBalance);
    error ExpiredRequest(uint256 requestExpiresAt, uint256 currentTime);
    error ParticipationAlreadyExists(bytes32 launchParticipationId);
    error MaxTokenAllocationReached(bytes32 launchGroupId);
    error MaxParticipantsReached(bytes32 launchGroupId);
    error MaxUserParticipationsReached(bytes32 launchGroupId, bytes32 userId);
    error InvalidRequestCurrency(address prevCurrency, address newCurrency);
    error InvalidRequestUserId(bytes32 prevUserId, bytes32 newUserId);
    error InvalidLaunchGroupStatus(
        bytes32 launchGroupId, LaunchGroupStatus expectedStatus, LaunchGroupStatus actualStatus
    );
    error ParticipationUpdatesNotAllowed(bytes32 launchGroupId, bytes32 launchParticipationId);
    error InvalidRefundRequest(bytes32 launchParticipationId);
    error LaunchGroupFinalizesAtParticipation(bytes32 launchGroupId);
    error InvalidWinner(bytes32 launchParticipationId);

    /// @notice Event for launch group creation
    event LaunchGroupCreated(bytes32 indexed launchGroupId);

    /// @notice Event for launch group update
    event LaunchGroupUpdated(bytes32 indexed launchGroupId);

    /// @notice Event for launch group currency update
    event LaunchGroupCurrencyUpdated(bytes32 indexed launchGroupId, address indexed currency);

    /// @notice Event for withdrawal address update
    event WithdrawalAddressUpdated(address indexed withdrawalAddress);

    /// @notice Event for launch group status update
    event LaunchGroupStatusUpdated(bytes32 indexed launchGroupId, LaunchGroupStatus status);

    /// @notice Event for participation registration
    event ParticipationRegistered(
        bytes32 indexed launchGroupId,
        bytes32 indexed launchParticipationId,
        bytes32 indexed userId,
        address user,
        uint256 currencyAmount,
        address currency
    );

    /// @notice Event for participation update
    event ParticipationUpdated(
        bytes32 indexed launchGroupId,
        bytes32 indexed launchParticipationId,
        bytes32 indexed userId,
        address user,
        uint256 currencyAmount,
        address currency
    );

    /// @notice Event for participation cancellation
    event ParticipationCancelled(
        bytes32 indexed launchGroupId,
        bytes32 indexed launchParticipationId,
        bytes32 indexed userId,
        address user,
        uint256 currencyAmount,
        address currency
    );

    /// @notice Event for winner selection
    event WinnerSelected(
        bytes32 indexed launchGroupId, bytes32 indexed launchParticipationId, bytes32 indexed userId, address user
    );

    /// @notice Event for refund claim
    event RefundClaimed(
        bytes32 indexed launchGroupId,
        bytes32 indexed launchParticipationId,
        bytes32 indexed userId,
        address user,
        uint256 currencyAmount,
        address currency
    );

    /// @notice Event for withdrawal
    event Withdrawal(address indexed user, address indexed currency, uint256 indexed currencyAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _withdrawalAddress, bytes32 _launchId, address _initialAdmin, uint8 _tokenDecimals)
        external
        initializer
    {
        __AccessControlEnumerable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        if (_initialAdmin == address(0) || _withdrawalAddress == address(0)) {
            revert InvalidRequest();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(MANAGER_ROLE, _initialAdmin);
        _grantRole(WITHDRAWAL_ROLE, _withdrawalAddress);
        _grantRole(OPERATOR_ROLE, _initialAdmin);
        _grantRole(SIGNER_ROLE, _initialAdmin);

        _setRoleAdmin(WITHDRAWAL_ROLE, WITHDRAWAL_ROLE);

        withdrawalAddress = _withdrawalAddress;
        launchId = _launchId;
        tokenDecimals = _tokenDecimals;
    }

    /// @notice Participate in a launch group
    function participate(ParticipationRequest calldata request, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
        onlyLaunchGroupStatus(request.launchGroupId, LaunchGroupStatus.ACTIVE)
    {
        _validateRequest(
            request.launchId, request.launchGroupId, request.chainId, request.requestExpiresAt, request.userAddress
        );
        _validateTimestamp(request.launchGroupId);
        if (!_validateRequestSignature(keccak256(abi.encode(request)), signature)) {
            revert InvalidSignature();
        }
        CurrencyConfig memory currencyConfig = _validateCurrency(request.launchGroupId, request.currency);
        // Do not allow replay of launch participation
        if (launchGroupParticipations[request.launchParticipationId].userId != bytes32(0)) {
            revert ParticipationAlreadyExists(request.launchParticipationId);
        }
        LaunchGroupSettings storage settings = launchGroupSettings[request.launchGroupId];
        // Check if max launchGroupParticipations per user is reached
        (, uint256 userNumParticipations) =
            _userParticipationsByLaunchGroup[request.launchGroupId].tryGet(request.userId);
        if (userNumParticipations >= settings.maxParticipationsPerUser) {
            revert MaxUserParticipationsReached(request.launchGroupId, request.userId);
        } else if (userNumParticipations == 0) {
            // Check if max participants for launch group is reached
            uint256 currTotalParticipants = _userParticipationsByLaunchGroup[request.launchGroupId].length();
            if (currTotalParticipants >= settings.maxParticipants) {
                revert MaxParticipantsReached(request.launchGroupId);
            }
        }
        // Calculate currency payment amount
        uint256 currencyAmount = _calculateCurrencyAmount(currencyConfig.tokenPriceBps, request.tokenAmount);
        if (currencyAmount < currencyConfig.minAmount || currencyAmount > currencyConfig.maxAmount) {
            revert InvalidCurrencyAmount(request.launchGroupId, request.currency, currencyAmount);
        }
        // Update participation info
        ParticipationInfo storage info = launchGroupParticipations[request.launchParticipationId];
        if (settings.finalizesAtParticipation) {
            info.isFinalized = true;
            // Validate available token allocation
            (, uint256 currTotalTokensSold) = _tokensSoldByLaunchGroup.tryGet(request.launchGroupId);
            if (currTotalTokensSold + request.tokenAmount > settings.maxTokenAllocation) {
                revert MaxTokenAllocationReached(request.launchGroupId);
            }
            _tokensSoldByLaunchGroup.set(request.launchGroupId, currTotalTokensSold + request.tokenAmount);
            (, uint256 withdrawableAmount) = _withdrawableAmountByCurrency.tryGet(request.currency);
            _withdrawableAmountByCurrency.set(request.currency, withdrawableAmount + currencyAmount);
        }
        info.userAddress = msg.sender;
        info.userId = request.userId;
        info.tokenAmount = request.tokenAmount;
        info.currencyAmount = currencyAmount;
        info.currency = request.currency;
        // Update total deposits for launch group
        (, uint256 currTotalDeposits) = _currencyDepositsByLaunchGroup[request.launchGroupId].tryGet(request.currency);
        _currencyDepositsByLaunchGroup[request.launchGroupId].set(request.currency, currTotalDeposits + currencyAmount);
        // Update total launchGroupParticipations for user and launch group
        (, uint256 currUserParticipations) =
            _userParticipationsByLaunchGroup[request.launchGroupId].tryGet(request.userId);
        _userParticipationsByLaunchGroup[request.launchGroupId].set(request.userId, currUserParticipations + 1);
        IERC20(request.currency).safeTransferFrom(msg.sender, address(this), currencyAmount);
        emit ParticipationRegistered(
            request.launchGroupId,
            request.launchParticipationId,
            request.userId,
            msg.sender,
            currencyAmount,
            request.currency
        );
    }

    /// @notice Update amount for existing participation
    function updateParticipation(UpdateParticipationRequest calldata request, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
        onlyLaunchGroupStatus(request.launchGroupId, LaunchGroupStatus.ACTIVE)
    {
        _validateRequest(
            request.launchId, request.launchGroupId, request.chainId, request.requestExpiresAt, request.userAddress
        );
        _validateTimestamp(request.launchGroupId);
        if (!_validateRequestSignature(keccak256(abi.encode(request)), signature)) {
            revert InvalidSignature();
        }
        CurrencyConfig memory currencyConfig = _validateCurrency(request.launchGroupId, request.currency);
        LaunchGroupSettings memory settings = launchGroupSettings[request.launchGroupId];
        ParticipationInfo storage prevInfo = launchGroupParticipations[request.prevLaunchParticipationId];
        if (settings.finalizesAtParticipation || prevInfo.isFinalized) {
            revert ParticipationUpdatesNotAllowed(request.launchGroupId, request.prevLaunchParticipationId);
        }
        ParticipationInfo storage newInfo = launchGroupParticipations[request.newLaunchParticipationId];
        // Validate currency is the same
        if (request.currency != prevInfo.currency) {
            revert InvalidRequestCurrency(prevInfo.currency, request.currency);
        }
        // Validate user id is the same
        if (request.userId != prevInfo.userId) {
            revert InvalidRequestUserId(prevInfo.userId, request.userId);
        }
        // Calculate new currency amount
        uint256 newCurrencyAmount = _calculateCurrencyAmount(currencyConfig.tokenPriceBps, request.tokenAmount);
        if (newCurrencyAmount < currencyConfig.minAmount || newCurrencyAmount > currencyConfig.maxAmount) {
            revert InvalidCurrencyAmount(request.launchGroupId, request.currency, newCurrencyAmount);
        }
        // Update new participation info
        newInfo.currencyAmount = newCurrencyAmount;
        newInfo.currency = request.currency;
        newInfo.userAddress = msg.sender;
        newInfo.userId = request.userId;
        newInfo.tokenAmount = request.tokenAmount;
        if (prevInfo.currencyAmount > newCurrencyAmount) {
            // Handle refund if new amount is less than old amount
            uint256 refundCurrencyAmount = prevInfo.currencyAmount - newCurrencyAmount;
            uint256 totalCurrencyDeposits = _currencyDepositsByLaunchGroup[request.launchGroupId].get(request.currency);
            if (totalCurrencyDeposits < refundCurrencyAmount) {
                revert InvalidBalances(refundCurrencyAmount, totalCurrencyDeposits);
            }
            _currencyDepositsByLaunchGroup[request.launchGroupId].set(
                request.currency, totalCurrencyDeposits - refundCurrencyAmount
            );
            IERC20(request.currency).safeTransfer(msg.sender, refundCurrencyAmount);
        } else if (newCurrencyAmount > prevInfo.currencyAmount) {
            // Take additional payment if new amount is greater than old amount
            uint256 additionalCurrencyAmount = newCurrencyAmount - prevInfo.currencyAmount;
            (, uint256 totalDeposits) = _currencyDepositsByLaunchGroup[request.launchGroupId].tryGet(request.currency);
            _currencyDepositsByLaunchGroup[request.launchGroupId].set(
                request.currency, totalDeposits + additionalCurrencyAmount
            );
            IERC20(request.currency).safeTransferFrom(msg.sender, address(this), additionalCurrencyAmount);
        }
        prevInfo.currencyAmount = 0;
        prevInfo.tokenAmount = 0;
        emit ParticipationUpdated(
            request.launchGroupId,
            request.newLaunchParticipationId,
            request.userId,
            msg.sender,
            request.tokenAmount,
            request.currency
        );
    }

    /// @notice Cancel existing participation
    function cancelParticipation(CancelParticipationRequest calldata request, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
        onlyLaunchGroupStatus(request.launchGroupId, LaunchGroupStatus.ACTIVE)
    {
        _validateRequest(
            request.launchId, request.launchGroupId, request.chainId, request.requestExpiresAt, request.userAddress
        );
        _validateTimestamp(request.launchGroupId);
        if (!_validateRequestSignature(keccak256(abi.encode(request)), signature)) {
            revert InvalidSignature();
        }
        LaunchGroupSettings memory settings = launchGroupSettings[request.launchGroupId];
        if (settings.finalizesAtParticipation) {
            revert ParticipationUpdatesNotAllowed(request.launchGroupId, request.launchParticipationId);
        }
        ParticipationInfo storage info = launchGroupParticipations[request.launchParticipationId];
        if (info.isFinalized) {
            revert ParticipationUpdatesNotAllowed(request.launchGroupId, request.launchParticipationId);
        }
        // Validate userId is the same which also checks if participation exists
        if (request.userId != info.userId) {
            revert InvalidRequestUserId(info.userId, request.userId);
        }

        uint256 refundCurrencyAmount = info.currencyAmount;
        (, uint256 totalCurrencyDeposits) = _currencyDepositsByLaunchGroup[request.launchGroupId].tryGet(info.currency);
        if (totalCurrencyDeposits < refundCurrencyAmount) {
            revert InvalidBalances(refundCurrencyAmount, totalCurrencyDeposits);
        }
        _currencyDepositsByLaunchGroup[request.launchGroupId].set(
            info.currency, totalCurrencyDeposits - refundCurrencyAmount
        );

        (, uint256 numUserParticipations) = _userParticipationsByLaunchGroup[request.launchGroupId].tryGet(info.userId);
        _userParticipationsByLaunchGroup[request.launchGroupId].set(info.userId, numUserParticipations - 1);

        // Refund currency to user
        IERC20(info.currency).safeTransfer(info.userAddress, refundCurrencyAmount);

        // Reset participation info
        info.tokenAmount = 0;
        info.currencyAmount = 0;
        emit ParticipationCancelled(
            request.launchGroupId,
            request.launchParticipationId,
            request.userId,
            msg.sender,
            refundCurrencyAmount,
            info.currency
        );
    }

    /// @notice Claim refund for unfinalized participation
    /// @dev Only allowed for completed launch groups
    function claimRefund(ClaimRefundRequest calldata request, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
        onlyLaunchGroupStatus(request.launchGroupId, LaunchGroupStatus.COMPLETED)
    {
        _validateRequest(
            request.launchId, request.launchGroupId, request.chainId, request.requestExpiresAt, request.userAddress
        );
        if (!_validateRequestSignature(keccak256(abi.encode(request)), signature)) {
            revert InvalidSignature();
        }
        ParticipationInfo storage info = launchGroupParticipations[request.launchParticipationId];
        if (request.userId != info.userId) {
            revert InvalidRequestUserId(info.userId, request.userId);
        }
        _processRefund(request.launchGroupId, request.launchParticipationId, info);
    }

    /// @notice Batch process refunds for unfinalized participations
    /// @dev Only allowed for completed launch groups
    function batchRefund(bytes32 launchGroupId, bytes32[] calldata launchParticipationIds)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        whenNotPaused
        onlyLaunchGroupStatus(launchGroupId, LaunchGroupStatus.COMPLETED)
    {
        for (uint256 i = 0; i < launchParticipationIds.length; i++) {
            ParticipationInfo storage info = launchGroupParticipations[launchParticipationIds[i]];
            _processRefund(launchGroupId, launchParticipationIds[i], info);
        }
    }

    /// @notice Finalize winners for a launch group
    /// @dev This should be done before launch group is marked as completed
    function finalizeWinners(bytes32 launchGroupId, bytes32[] calldata winnerLaunchParticipationIds)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        onlyLaunchGroupStatus(launchGroupId, LaunchGroupStatus.ACTIVE)
    {
        LaunchGroupSettings storage settings = launchGroupSettings[launchGroupId];
        if (settings.finalizesAtParticipation) {
            revert LaunchGroupFinalizesAtParticipation(launchGroupId);
        }

        uint256 additionalTokensSold = 0;
        (, uint256 currTotalTokensSold) = _tokensSoldByLaunchGroup.tryGet(launchGroupId);
        for (uint256 i = 0; i < winnerLaunchParticipationIds.length; i++) {
            ParticipationInfo storage info = launchGroupParticipations[winnerLaunchParticipationIds[i]];
            if (info.tokenAmount == 0 || info.isFinalized || info.currencyAmount == 0) {
                revert InvalidWinner(winnerLaunchParticipationIds[i]);
            }

            additionalTokensSold += info.tokenAmount;
            if (settings.maxTokenAllocation < currTotalTokensSold + additionalTokensSold) {
                revert MaxTokenAllocationReached(launchGroupId);
            }

            info.isFinalized = true;
            (, uint256 withdrawableAmount) = _withdrawableAmountByCurrency.tryGet(info.currency);
            _withdrawableAmountByCurrency.set(info.currency, withdrawableAmount + info.currencyAmount);

            emit WinnerSelected(launchGroupId, winnerLaunchParticipationIds[i], info.userId, info.userAddress);
        }
        _tokensSoldByLaunchGroup.set(launchGroupId, currTotalTokensSold + additionalTokensSold);
    }

    /// @notice Withdraw funds for currency
    /// @dev All launch groups must be completed. We only allow withdrawing funds from finalized participations.
    function withdraw(address currency, uint256 amount) external nonReentrant whenNotPaused onlyRole(WITHDRAWAL_ROLE) {
        bytes32[] memory launchGroupIds = _launchGroups.values();
        for (uint256 i = 0; i < launchGroupIds.length; i++) {
            if (launchGroupSettings[launchGroupIds[i]].status != LaunchGroupStatus.COMPLETED) {
                revert InvalidLaunchGroupStatus(
                    launchGroupIds[i], LaunchGroupStatus.COMPLETED, launchGroupSettings[launchGroupIds[i]].status
                );
            }
        }
        (, uint256 withdrawableAmount) = _withdrawableAmountByCurrency.tryGet(currency);
        if (withdrawableAmount < amount) {
            revert InvalidBalances(amount, withdrawableAmount);
        }
        _withdrawableAmountByCurrency.set(currency, withdrawableAmount - amount);
        IERC20(currency).safeTransfer(withdrawalAddress, amount);
        emit Withdrawal(withdrawalAddress, currency, amount);
    }

    /// @notice Calculate currency payment amount based on bps and token amount
    function _calculateCurrencyAmount(uint256 tokenPriceBps, uint256 tokenAmount) internal view returns (uint256) {
        return Math.mulDiv(tokenPriceBps, tokenAmount, 10 ** tokenDecimals);
    }

    /// @notice Validate request signature
    function _validateRequestSignature(bytes32 messageHash, bytes calldata signature) private view returns (bool) {
        address signer = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(messageHash), signature);
        bool success = hasRole(SIGNER_ROLE, signer);
        return success;
    }

    function _processRefund(bytes32 launchGroupId, bytes32 launchParticipationId, ParticipationInfo storage info)
        private
    {
        if (info.isFinalized || info.currencyAmount == 0 || info.tokenAmount == 0) {
            revert InvalidRefundRequest(launchParticipationId);
        }
        uint256 refundCurrencyAmount = info.currencyAmount;
        info.tokenAmount = 0;
        info.currencyAmount = 0;
        (, uint256 totalCurrencyDeposits) = _currencyDepositsByLaunchGroup[launchGroupId].tryGet(info.currency);
        if (totalCurrencyDeposits < refundCurrencyAmount) {
            revert InvalidBalances(refundCurrencyAmount, totalCurrencyDeposits);
        }
        _currencyDepositsByLaunchGroup[launchGroupId].set(info.currency, totalCurrencyDeposits - refundCurrencyAmount);
        IERC20(info.currency).safeTransfer(info.userAddress, refundCurrencyAmount);
        emit RefundClaimed(
            launchGroupId, launchParticipationId, info.userId, info.userAddress, refundCurrencyAmount, info.currency
        );
    }

    /// @notice Validates common request parameters
    function _validateRequest(
        bytes32 _launchId,
        bytes32 _launchGroupId,
        uint256 _chainId,
        uint256 _requestExpiresAt,
        address _userAddress
    ) private view {
        if (
            _launchId != launchId || _chainId != block.chainid || msg.sender != _userAddress
                || !_launchGroups.contains(_launchGroupId)
        ) {
            revert InvalidRequest();
        }

        if (_requestExpiresAt <= block.timestamp) {
            revert ExpiredRequest(_requestExpiresAt, block.timestamp);
        }
    }

    /// @notice Validates launch group timestamp
    function _validateTimestamp(bytes32 _launchGroupId) private view {
        LaunchGroupSettings memory settings = launchGroupSettings[_launchGroupId];
        if (block.timestamp < settings.startsAt || block.timestamp > settings.endsAt) {
            revert InvalidRequest();
        }
    }

    /// @notice Validate currency is enabled for a launch group
    function _validateCurrency(bytes32 _launchGroupId, address _currency)
        private
        view
        returns (CurrencyConfig memory)
    {
        if (!_launchGroupCurrencies[_launchGroupId][_currency].isEnabled) {
            revert InvalidRequest();
        }
        return _launchGroupCurrencies[_launchGroupId][_currency];
    }

    /// @notice Validate currency config
    function _validateCurrencyConfig(CurrencyConfig calldata currencyConfig) private pure {
        if (currencyConfig.tokenPriceBps == 0) {
            revert InvalidRequest();
        }
    }

    /// @notice Create a new launch group
    function createLaunchGroup(
        bytes32 launchGroupId,
        address initialCurrency,
        CurrencyConfig calldata initialCurrencyConfig,
        LaunchGroupSettings calldata settings
    ) external onlyRole(MANAGER_ROLE) {
        if (_launchGroups.contains(launchGroupId)) {
            revert InvalidRequest();
        }
        _validateCurrencyConfig(initialCurrencyConfig);
        launchGroupSettings[launchGroupId] = settings;
        _launchGroupCurrencies[launchGroupId][initialCurrency] = initialCurrencyConfig;
        _launchGroups.add(launchGroupId);
        emit LaunchGroupCreated(launchGroupId);
    }

    /// @notice Set launch group currency config
    function setLaunchGroupCurrency(bytes32 launchGroupId, address currency, CurrencyConfig calldata currencyConfig)
        external
        onlyRole(MANAGER_ROLE)
    {
        _validateCurrencyConfig(currencyConfig);
        _launchGroupCurrencies[launchGroupId][currency] = currencyConfig;
        emit LaunchGroupCurrencyUpdated(launchGroupId, currency);
    }

    /// @notice Enable or disable a launch group currency
    function toggleLaunchGroupCurrencyEnabled(bytes32 launchGroupId, address currency, bool isEnabled)
        external
        onlyRole(MANAGER_ROLE)
    {
        _launchGroupCurrencies[launchGroupId][currency].isEnabled = isEnabled;
        emit LaunchGroupCurrencyUpdated(launchGroupId, currency);
    }

    /// @notice Set launch group settings
    /// @dev The finalizesAtParticipation setting can only be updated before the launch group is active
    function setLaunchGroupSettings(bytes32 launchGroupId, LaunchGroupSettings calldata settings)
        external
        onlyRole(MANAGER_ROLE)
    {
        if (!_launchGroups.contains(launchGroupId)) {
            revert InvalidRequest();
        }
        LaunchGroupSettings memory prevSettings = launchGroupSettings[launchGroupId];
        if (
            prevSettings.status != LaunchGroupStatus.PENDING
                && settings.finalizesAtParticipation != prevSettings.finalizesAtParticipation
        ) {
            revert InvalidRequest();
        }
        launchGroupSettings[launchGroupId] = settings;
        emit LaunchGroupUpdated(launchGroupId);
    }

    /// @notice Set launch identifier
    function setLaunchId(bytes32 _launchId) external onlyRole(MANAGER_ROLE) {
        launchId = _launchId;
    }

    /// @notice Set launch group status
    /// @dev Status changes to pending are not allowed since other statuses can involve state changes
    function setLaunchGroupStatus(bytes32 launchGroupId, LaunchGroupStatus status) external onlyRole(MANAGER_ROLE) {
        if (status == LaunchGroupStatus.PENDING) {
            revert InvalidRequest();
        }
        launchGroupSettings[launchGroupId].status = status;
        emit LaunchGroupStatusUpdated(launchGroupId, status);
    }

    /// @notice Set withdrawal address
    function setWithdrawalAddress(address _withdrawalAddress) external onlyRole(WITHDRAWAL_ROLE) {
        if (_withdrawalAddress == address(0)) {
            revert InvalidRequest();
        }
        withdrawalAddress = _withdrawalAddress;
        emit WithdrawalAddressUpdated(_withdrawalAddress);
    }

    /// @notice Get all launch group ids
    function getLaunchGroups() external view returns (bytes32[] memory) {
        return _launchGroups.values();
    }

    /// @notice Get total number of launch groups
    function getTotalLaunchGroups() external view returns (uint256) {
        return _launchGroups.length();
    }

    /// @notice Get launch group status for a launch group
    function getLaunchGroupStatus(bytes32 launchGroupId) external view returns (LaunchGroupStatus) {
        return launchGroupSettings[launchGroupId].status;
    }

    /// @notice Get launch group settings for a launch group
    function getLaunchGroupSettings(bytes32 launchGroupId) external view returns (LaunchGroupSettings memory) {
        return launchGroupSettings[launchGroupId];
    }

    /// @notice Get currency config for a launch group and currency
    function getLaunchGroupCurrencyConfig(bytes32 launchGroupId, address currency)
        external
        view
        returns (CurrencyConfig memory)
    {
        return _launchGroupCurrencies[launchGroupId][currency];
    }

    /// @notice Get participation info for a launch participation
    function getParticipationInfo(bytes32 launchParticipationId) external view returns (ParticipationInfo memory) {
        return launchGroupParticipations[launchParticipationId];
    }

    /// @notice Get all user ids for a launch group
    /// @dev This should not be called by other state-changing functions to avoid gas issues
    function getLaunchGroupParticipantUserIds(bytes32 launchGroupId) external view returns (bytes32[] memory) {
        return _userParticipationsByLaunchGroup[launchGroupId].keys();
    }

    /// @notice Get total number of unique participants for a launch group
    /// @dev Note that this is based on user identifier rather than user address
    function getNumUniqueParticipantsByLaunchGroup(bytes32 launchGroupId) external view returns (uint256) {
        return _userParticipationsByLaunchGroup[launchGroupId].length();
    }

    /// @notice Get number of participations for a user in a launch group
    function getNumParticipationsByUser(bytes32 launchGroupId, bytes32 userId) external view returns (uint256) {
        (, uint256 count) = _userParticipationsByLaunchGroup[launchGroupId].tryGet(userId);
        return count;
    }

    /// @notice Get withdrawable amount for a currency
    function getWithdrawableAmountByCurrency(address currency) external view returns (uint256) {
        (, uint256 amount) = _withdrawableAmountByCurrency.tryGet(currency);
        return amount;
    }

    /// @notice Get all currencies with deposits for a launch group
    function getCurrenciesWithDeposits(bytes32 launchGroupId) external view returns (address[] memory) {
        return _currencyDepositsByLaunchGroup[launchGroupId].keys();
    }

    /// @notice Get total deposits for a currency for a launch group
    function getDepositsByCurrency(bytes32 launchGroupId, address currency) external view returns (uint256) {
        (, uint256 deposits) = _currencyDepositsByLaunchGroup[launchGroupId].tryGet(currency);
        return deposits;
    }

    /// @notice Get total tokens sold for a launch group
    function getTokensSoldByLaunchGroup(bytes32 launchGroupId) external view returns (uint256) {
        (, uint256 tokensSold) = _tokensSoldByLaunchGroup.tryGet(launchGroupId);
        return tokensSold;
    }

    /// @notice Pause the contract
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Modifier to check launch group status
    modifier onlyLaunchGroupStatus(bytes32 launchGroupId, LaunchGroupStatus status) {
        if (launchGroupSettings[launchGroupId].status != status) {
            revert InvalidLaunchGroupStatus(launchGroupId, status, launchGroupSettings[launchGroupId].status);
        }
        _;
    }
}
