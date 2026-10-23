# SqueekChain (SQK)

A fixed-supply ERC-20 token for an IdentityMD custom-token launch on Ethereum (chain id 1).

| Setting | Value |
| --- | --- |
| Solidity contract | `SqueekChain` (`src/SqueekChain.sol`) |
| Token name | `SqueekChain` |
| Token symbol | `SQK` |
| Decimals | 18 |
| Total supply | 1,000,000,000 SQK = `1000000000000000000000000000` minor units (10^27) |
| Constructor arguments | none |
| Mint | the whole supply, once, in the constructor, to `msg.sender` |
| Owner / admin | none |

## Behaviour

- Standard ERC-20: `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`, `transfer`, `approve`,
  `allowance`, `transferFrom`, with `Transfer` and `Approval` events.
- The supply is a compile-time constant (`TOTAL_SUPPLY`). `totalSupply()` returns it and nothing
  can change it: there is no `mint`, no `burn`, no `burnFrom`.
- No owner, no pause, no blocklist, no freeze, no seize, no fee or tax on transfer, no upgrade
  path, no `receive`/`fallback`. The deployer holds the mint and nothing else: after deployment it
  is an ordinary holder.
- An allowance of `type(uint256).max` is unlimited and is not decreased on `transferFrom`.
- Failures revert with OpenZeppelin v5-style custom errors (`ERC20InsufficientBalance`,
  `ERC20InvalidReceiver`, `ERC20InsufficientAllowance`, `ERC20InvalidSpender`, ...).
- The contract imports nothing and calls no other contract. Its runtime contains no
  `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`.

## Assumptions

- The brief asks for a plain token: name, symbol, supply, and a one-time mint to the deployer.
  No transfer rules (tax, burn, reflection, vesting, governance) were requested, so none exist.
- "Deployer" means `msg.sender` of the constructor. In the IMD launch that is the ProjectFactory,
  which receives the full supply and pays it out (swarm share to the MerkleDistributor, pool seed
  through the Uniswap v4 PoolManager, remainder to the requester). Because transfers move exactly
  what they say, no launch address needs an exemption and the constructor takes no arguments.
- Decimals are 18 and the manifest's `token.totalSupply` must be `1000000000000000000000000000`.

## Deployment parameters

The launch is performed by IMD's deployer through the factory; nothing in this repository deploys,
broadcasts or signs. Values the manifest step needs:

- `token.contract`: `SqueekChain`
- `token.name`: `SqueekChain`
- `token.symbol`: `SQK`
- `token.decimals`: `18`
- `token.constructorArgs`: `[]`
- `token.totalSupply`: `1000000000000000000000000000`
- Application contracts: none.
- Pool: paired with IMD (`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`), fee 12500, tick spacing 60,
  initial price `79228162514264337593543950336`; the deployer derives the opening price from the
  requester's economics (80% of the supply to the pool at a 4,500 IMD cap, remainder to
  `0x206f5dbf4f135c6183b5a5b99327fa0be34cb4d9`). These are the launch's, not settings of the token.

Build settings in `foundry.toml`: `solc = "0.8.26"`, `evm_version = "cancun"`, optimizer on with
200 runs, `bytecode_hash = "none"` so the deployed bytes are reproducible without a metadata hash.

## Operational responsibilities

- There is nothing to configure after launch: no owner, no setters, no "After launch" steps.
- Holders are responsible for their own keys and approvals. The token cannot recover tokens sent
  to a wrong address or to the token contract itself.
- Integrators should treat SQK as a standard, non-rebasing, fee-free ERC-20 with a constant supply.
- Tests are not an audit. Any contract that later holds SQK on behalf of users should get an
  independent adversarial review before release.

## Testing

```
forge build
forge test
forge fmt --check
```

The tests in `test/SqueekChain.t.sol` cover metadata, the one-time mint and its event, transfer and
transferFrom success paths, every revert path with its exact error, the absence of mint, pause,
blocklist, freeze and seize entry points (tried from a stranger and from the deployer), the
runtime-code opcode floor, and fuzzed conservation of supply and allowance accounting.

The tests depend on no vendored library. `test/support/Test.sol` declares the subset of Foundry's
cheatcode interface the tests use (prank, expectRevert, expectEmit, assume, label, and forge's
native assertion cheatcodes), with the same signatures as forge-std's `Vm.sol`, so forge serves
them itself. Fuzz tests are deterministic for any seed: they bound their inputs by modulo rather
than rejecting them.

Known limitation of this submission: the worker machine's command sandbox refused to start any
process (`apply-seccomp ... Permission denied`), so `forge build`, `forge test` and `forge fmt`
could not be run here before submission. The sources were written against solc 0.8.26 and the
forge 1.8 cheatcode set and reviewed by hand; the verifier's run is the first compile.
