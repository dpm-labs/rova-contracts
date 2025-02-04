# Rova Launch Contracts

Rova is a platform for allowing users to participate in token launches.

## Definitions

### Launch

The [`Launch`](src/Launch.sol) contract is the main contract that manages the state and launch groups and represents a single launch. It will be deployed for each launch and will be upgradable.

The goal is to facilitate launch participation and payment processing for users, while providing a flexible backend system for orchestrating different launch structures and requirements.

### Launch Groups

Launch groups allow for users to participate into different groups under a single launch. Participation eligibility for groups is primarily done in our backend since it requires offchain verification of user information like KYC status, social accounts, etc. This allows for a more flexible participation system where there can be different rules for different groups, like different start and end times, different maximum allocations, different launch structures (FCFS, raffles), etc.

Since requests must be first "approved" by our backend, we will have backend signer(s) to sign all state changing user requests. These signatures will be submitted in request calldata and validated in the `Launch` contract.

Since different launch groups can have different launch structures, we will have a `LaunchGroupSettings` struct that contains the settings for and the status of the launch group. Since launch groups will need to be tracked in our backend, we will associate a launch group identifier from our backend with each launch group.

### Launch Participation

Multiple ERC20 tokens can be supported payment currency for launch groups.

Launch group relationships, accepted currencies, and other configurations will be set in our backend. Only required configs like currency and currency bps (price per token, scales on the currency decimals) will be sent in request calldata when users are participating in a launch group.

When a user participates in a launch group, our backend will generate a launch participation identifier that is unique to the user, launch group, and launch. This id will be used to identify the participation in all state changing functions.

Rova users can link and use multiple wallets to participate in the launch, so participations are also linked to a backend-generated user identifier.

### Roles

The `Launch` contract uses the OpenZeppelin Access Control Enumerable library to manage roles.

- `DEFAULT_ADMIN_ROLE`: The default admin role, role admin for all other roles except `WITHDRAWAL_ROLE`.
- `MANAGER_ROLE`: The manager role for the launch, can update launch group settings and status.
- `OPERATOR_ROLE`: The operator role for the launch. This will be the role for automated actions like selecting winners for a raffle or auction or performing batch refunds.
- `SIGNER_ROLE`: The signer role for the launch. This will be the role for signing all user requests.
- `WITHDRAWAL_ROLE`: The withdrawal role for the launch. This will be the role for withdrawing funds to the withdrawal address. It is it's own role admin.

### Launch Group Status

#### PENDING

Launch group is pending:

- This should be the initial status of a launch group when we set it up to allow us to review and confirm all settings before making it active.
- This is the only status where update to `finalizesAtParticipation` in launch group settings is allowed. This is to prevent unexpected behavior when the launch group is active since once a participation is finalized, it can't be updated and the deposited funds are added to the withdrawable balance.

#### ACTIVE

Launch group is active:

- Users can participate in the launch group between `startsAt` and `endsAt`.
- Users can make updates to or cancel their participation until `endsAt` if `finalizesAtParticipation` is false.
- Participation can be finalized during this status as well by operators, such as selecting winners for a raffle or auction. Once finalized, users can't make updates to or cancel their participation.

#### PAUSED

Launch group is paused:

- Any action that requires ACTIVE or COMPLETED status will revert, like participation registration, updates, selecting winners, refunds, or withdrawals.
- This allows us to pause actions on a launch group without having to update the status to one that may result in side effects since the other statuses control permissioning for other write actions.

#### COMPLETED

Launch group is completed:

- Users can claim refunds if their participation is not finalized, e.g. they didn't win a raffle or auction.
- Withdrawable balances per payment currency can be withdrawn to the withdrawal address once all launch groups are completed for the launch.

## Development

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
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
