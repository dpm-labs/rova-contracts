# Rova Launch Contracts

Rova is a platform for allowing users to participate in token launches. These contracts are used to facilitate participation and payment processing for Rova token sale launches.

## Definitions

### Launch

The [`Launch`](src/Launch.sol) contract is the main contract that manages the state and launch groups and represents a single project token sale launch. It will be deployed for each launch and will be upgradable.

The goal of this contract is to facilitate launch participation and payment processing for users, and is meant to be used in conjunction with our backend system to orchestrate different launch structures and additional validation requirements (e.g. KYC).

### Launch Groups

Launch groups allow for users to participate into different groups under a single launch. This allows for a more flexible participation system where there can be different rules for different groups, like different start and end times, maximum allocations, launch structures (FCFS, raffles), payment currencies (ERC20), etc. Participation eligibility for groups is primarily done in our backend since it requires offchain verification of user information like KYC status, social accounts, etc.

Since requests must be first "approved" by our backend, backend signer(s) with the signer role will sign all state-changing user requests. These signatures will be submitted in request calldata and validated in the `Launch` contract. See [Appendix: Signing Requests](#signing-requests) for more details.

The `LaunchGroupSettings` struct contains the settings for the launch group to allow for different launch structures. It also contains the status of the launch group to track launch group lifecycle. Since launch groups will need to be tracked in our backend, a launch group identifier from our backend is associated with each launch group registered within the `Launch` contract.

#### Finalizes at Participation

This is a setting in the `LaunchGroupSettings` struct that determines if user participation is considered complete during the `participate` function. It can only be updated before the launch group is active.

When a launch group has `finalizesAtParticipation` set to `true`, the participation is considered complete and not updatable/cancellable. Users can participate again in the same launch group as long as they stay within the same launch group's allocation limits.

When a launch group has `finalizesAtParticipation` set to `false`, the participation can be updated or cancelled until the launch group ends. Participation will be finalized manually by operators via the `finalizeWinners` function, which typically happens after the launch group particpation period ends (tracked by the `endsAt` timestamp).

- If users want to update their participation amount, they can do so until the launch group ends via the `updateParticipation` function.
- If users want to cancel their participation compl, they can do so until the launch group ends via the `cancelParticipation` function. If the participation is cancelled, the user is allowed to participate again in the same launch group via the `participate` function.

### Payment Currency

Each launch group can have a multiple accepted payment currencies. These are registered in a mapping of launch group id to currency address to currency config. Users will specify the currency they want to use when participating in a launch group and we will validate the requested token amount and payment amount against the configured token price per currency.

Typically, payment currencies are USDC and USDT. However, in some cases we provide the option for projects to offer other currencies. In these cases, the currency must be reviewed by Rova before it can be used in a launch group to make sure there are no weird behaviors like rebasing or fee on transfer. The project will need to provide a fixed price conversion for each currency they want to support before the launch. Token price for each payment currency would not be updated after the launch group is active. If projects want to support additional currencies or price conversions after the launch group is active, Rova will review and create a new launch group for the new currency.

See [Appendix: How to Calculate Token Price](#how-to-calculate-token-price) for more details on how we calculate the token price per currency.

### Launch Participation

When a user participates in a launch group, Rova backend will generate a launch participation identifier that is unique to the user, launch group, and launch. This id will be used to identify the participation in all state-changing functions and across a launch groups' lifecycle.

Rova users can link and use different wallets to fund their participation, so a backend-generated user identifier is linked to all participations for a user. Validations are done against that user identifier instead of the calling wallet address.

### Roles

The `Launch` contract uses the OpenZeppelin Access Control Enumerable library to manage roles.

- `DEFAULT_ADMIN_ROLE`: The default admin role, role admin for all other roles except `WITHDRAWAL_ROLE`.
- `MANAGER_ROLE`: The manager role for the launch, can update launch group settings and status.
- `OPERATOR_ROLE`: The operator role for the launch. This will be the role for automated actions like selecting winners for a raffle or auction or performing batch refunds.
- `SIGNER_ROLE`: The signer role for the launch. This will be the role for signing all user requests.
- `WITHDRAWAL_ROLE`: The withdrawal role for the launch. This will be the role for withdrawing funds to the withdrawal address. It is it's own role admin.

### Launch Group Status

This section describes the statuses of and the lifecycle of a launch group.

#### PENDING

Launch group is pending:

- This should be the initial status of a launch group when we set it up to allow us to review and confirm all settings before making it active.
- This is the only status where update to `finalizesAtParticipation` in launch group settings is allowed. This is to prevent unexpected behavior when the launch group is active since once a user's participation is finalized, it can't be updated and the deposited funds are added to the withdrawable balance.

#### ACTIVE

Launch group is active:

- Users can participate in the launch group between `startsAt` and `endsAt` timestamps.
- Users can make updates to or cancel their participation until `endsAt` if the launch group `finalizesAtParticipation` setting is false.
- Participation can be finalized during this status as well by operators, such as selecting winners for a raffle or auction. Once finalized, users can't make updates to or cancel their participation.

#### PAUSED

Launch group is paused:

- This allows us to pause actions on a launch group without having to update the status to one that may result in side effects since the other statuses control permissioning for other write actions.
- Any action that requires ACTIVE or COMPLETED status will revert, like participation registration, updates, selecting winners, refunds, or withdrawals.
- This is separate from the launch contract's `paused` state since it applies to individual launch groups.

#### COMPLETED

Launch group is completed:

- Users can claim refunds if their participation is not finalized, e.g. they didn't win a raffle or auction. Operators can help batch refund user participations that are not finalized too.
- Withdrawable balances per payment currency can be withdrawn to the withdrawal address once all launch groups under the launch are completed.

## Development

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

For coverage:

```shell
$ forge coverage --ir-minimum
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

Set `PRIVATE_KEY` in `.env` and run:

```shell
$ forge script script/Deploy.s.sol:DeployScript --rpc-url <your_rpc_url> --broadcast

```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Appendix

### How to Calculate Token Price

Token price calculation based on the payment currency token, taking in account the project token decimals and currency token decimals.

This is to ensure accurate accounting up to available decimals for how many tokens a person has purchased.

#### Variables

- **Project token decimals (`PTD`)**
  - Example: $TOKEN is 8 decimals
- **Currency token decimals (`CTD`)**
  - Example: $USDC is 6 decimals
- **Intended price conversion (`P`)**
  - This is the intended readable conversion, not taking into account each token’s decimals
  - Example: For “1 $TOKEN = 1.5 $USDC”, P would be 1.5

#### Token Price Calculation

Steps to calculate `tokenPriceBps`, which is the price of the project token per currency token.

```
tokenPriceBps = P * (10^CTD)
```

Example: 1 $TOKEN = 1.5 $USDC, where $USDC has 6 decimals and $TOKEN is the project token

```
P = 1.5
CTD = 6
tokenPriceBps = 1.5 * (10^6) = 1500000
```

#### Currency Amount Calculation

Steps to calculate `currencyAmount`, which is the amount a user would pay in their currency of choice for a given `tokenAmount` of the project token.

```
tokenPriceBps = P * (10^CTD)
maxBps = 10^PTD
currencyAmount = (tokenPriceBps * tokenAmount) / maxBps
currencyAmount = (P * (10^CTD) * tokenAmount) / (10^PTD)
```

### Signing Requests

Since requests must be first "approved" by our backend, backend signer(s) with the signer role will sign all user requests. The generated signatures will be provided to users to include in their transaction calldata.

#### Request Parameters

Here are the request parameters and where they come from for the signer to sign. Some will be passed in by the user making the request and some will be determined by our backend and provided to the user.

- `chainId` - This would not come from user input. The value being signed is the chainId of the chain the contract is deployed on. The contract addresses and the chain they are deployed on are mapped in our backend.

- `launchId` - This would not come from user input. The value being signed is the launchId of the Launch contract and is mapped in our backend but also configured in the Launch contract.

- `launchGroupId` - This would come from user input, to signal which group the user wants to participate in. Before signing, the backend would validate that the launchGroupId is valid for the launchId and that the participation being updated is the same group.

- `launchParticipationId` - This is provided to the user and would not come from user input. This is generated by the backend once validations are done and is unique to the user, launch group, and launch.

  - For `cancelParticipation` requests, our backend would validate that the `launchParticipationId` is valid for the `launchGroupId` and that it the participation belongs to the same user making the cancellation request.

- `prevLaunchParticipationId` - (applies to `updateParticipation` requests) This would come from user input. Before signing, the backend would validate that the prevLaunchParticipationId is valid for the launchGroupId and that it belongs to the user making the request.

- `newLaunchParticipationId` - (applies to `updateParticipation` requests) This is provided to the user and would not come from user input. This will be generated by the backend once validations are done and is unique to the user, launch group, and launch.

- `userId` - This would not come from direct user input. A user access token is required in request headers when users request for the signature to authenticate the user. Our backend will be able to determine the `userId` from the user access token and this is the value that will be used in the request.

- `userAddress` - This would come from user input. Before signing, our backend would validate that the `userAddress` is not sanctioned.

- `tokenAmount` - This would come from user input. Before signing, our backend would validate that the `tokenAmount` is within the minimum and maximum token amount per user for the launch group.

- `currency` - This would come from user input. Before signing, our backend would validate that the currency is supported and enabled for the launch group. Currency configuration is also tracked in the Launch contract.

- `requestExpiresAt` - This is provided to the user for the request and would not come from user input. Our backend generates this timestamp when the user requests for the signature.
