# Season Audit Notes

This document covers the scope of the Seasons Audit of the Aragon VE Governance repo.

## Background

Aragon released our VE Governance plugin in October 2024. Since then we've deployed it across several large projects such as ModeDAO, PufferDAO, BedrockDAO and more.

This release adds the concept of seasons to allow resetting the voting power of the voters.
The goal of this audit is to ensure that the new season functionality is secure and works as intended.

1. **Clock**: The clock contract is responsible for managing the time and seasons. It includes functions to start and end seasons, as well as to check the current season.
2. **Curve**: The curve contract is responsible for managing the voting power of the locked tokens. It includes functions to calculate the voting power based on the current season.
3. **Voter**: The voter contract is responsible for managing the voting process. It includes functions to vote on the gauges, as well as to check the current status of the votes.
4. **Setup**: The setup contract is responsible for preparing the installation of the plugin.

## Audit Scope

The following files can be considered as part of the audit:

| Contract Group | Contract Name                       | In Scope | Details                    |
| -------------- | ----------------------------------- | -------- | -------------------------- |
| `clock`        | ClockSeason.sol                     | ✅       | Season-specific logic      |
| `clock`        | IClockSeason.sol                    | ✅       | Interface                  |
| `curve`        | QuadraticIncreasingCurveSeason.sol  | ✅       | Season-specific variant    |
| `factory`      | GaugesDaoFactorySeason.sol          | ✅       | Season-specific            |
| `setup`        | GaugeVoterSetupSeason.sol           | ✅       | Season-specific setup      |
| `voting`       | TokenGaugeVoterSeason.sol           | ✅       | Season-specific logic      |


The following files are not in scope:

| Contract Group | Contract Name                       | In Scope | Details                    |
| -------------- | ----------------------------------- | -------- | -------------------------- |
| `clock`        | Clock.sol                           | ❌       | Core clock contract        |
| `clock`        | Clock_v1_2_0.sol                    | ❌       | Versioned implementation   |
| `clock`        | IClock_v1_2_0.sol                   | ❌       | Interface                  |
| `clock`        | IClock.sol                          | ❌       | Interface                  |
| `curve`        | QuadraticIncreasingCurve.sol        | ❌       | Quadratic variant          |
| `curve`        | IEscrowCurveIncreasing.sol          | ❌       | Interface                  |
| `curve`        | LinearIncreasingCurve.sol           | ❌       | Main curve logic           |
| `curve`        | LinearIncreasingCurveNoSupply.sol   | ❌       | Variant without supply     |
| `curve`        | IEscrowCurveIncreasing_v1_2_0.sol   | ❌       | Interface                  |
| `delegation`   | EscrowIVotesAdapter.sol             | ❌       | IVotes adapter             |
| `delegation`   | IEscrowIVotesAdapter.sol            | ❌       | Interface                  |
| `escrow`       | VotingEscrowIncreasing.sol          | ❌       | Main escrow contract       |
| `escrow`       | IVotingEscrowIncreasing.sol         | ❌       | Interface                  |
| `escrow`       | VotingEscrowIncreasing_v1_2_0.sol   | ❌       | Versioned implementation   |
| `escrow`       | IVotingEscrowIncreasing_v1_2_0.sol  | ❌       | Interface                  |
| `factory`      | GaugesDaoFactory.sol                | ❌       | Base factory               |
| `factory`      | GaugesDaoFactory_v1_1_0.sol         | ❌       | Versioned implementation   |
| `factory`      | GaugesDaoFactory_v1_2_0.sol         | ❌       | Versioned implementation   |
| `factory`      | GaugesDaoFactory_v1_3_0.sol         | ❌       | Versioned implementation   |
| `factory`      | UpgradeFactory_v1_0_0\_\_v1_3_0.sol | ❌       | Upgrade utility            |
| `libs`         | CurveConstantLib.sol                | ❌       | Math/constants lib         |
| `libs`         | ProxyLib.sol                        | ❌       | Proxy utilities            |
| `libs`         | SignedFixedPointMathLib.sol         | ❌       | Math lib                   |
| `lock`         | Lock.sol                            | ❌       | Main lock contract         |
| `lock`         | Lock_v1_2_0.sol                     | ❌       | Versioned implementation   |
| `lock`         | ILock.sol                           | ❌       | Interface                  |
| `lock`         | IERC721EMB.sol                      | ❌       | ERC721 interface extension |
| `queue`        | ExitQueue.sol                       | ❌       | Queue implementation       |
| `queue`        | IExitQueue.sol                      | ❌       | Interface                  |
| `setup`        | GaugeVoterSetup.sol                 | ❌       | Setup logic                |
| `setup`        | GaugeVoterSetup_v1_1_0.sol          | ❌       | Versioned setup            |
| `setup`        | GaugeVoterSetup_v1_2_0.sol          | ❌       | Versioned setup            |
| `setup`        | GaugeVoterSetup_v1_3_0.sol          | ❌       | Versioned setup            |
| `voting`       | TokenGaugeVoter.sol                 | ❌       | Token-based voter          |
| `voting`       | TokenGaugeVoter_v1_1_0.sol          | ❌       | Versioned implementation   |
| `voting`       | IGaugeVoter.sol                     | ❌       | Interface                  |
| `voting`       | ITokenGaugeVoter.sol                | ❌       | Interface                  |
| `voting`       | AddressGaugeVoter.sol               | ❌       | Address-based voter        |
| `voting`       | IAddressGaugeVoter.sol              | ❌       | Interface                  |
