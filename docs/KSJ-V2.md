# KSJ four-compartment V2

New version for the KSJ-4 grid cabinet, independent from the legacy three-track VendingMachine deployment. Contracts live in `src/ksj/`. The frontend is a fresh repository: https://github.com/communetxyz/ksj-vend-app.

Each slot represents the whole contents of one locked compartment. A successful purchase transfers the configured ERC20 price into the contract, records buyer/slot/amount, emits Purchased, and marks that compartment unavailable. Only the owner can restock or refund. The buyer submits the expected price so a price change cannot silently change the charge. A refund does not open or restock a compartment. Retain funds in the contract until pickup/refund issues are resolved.

The immutable owner and token are set at deployment. No production deployment is performed by this change. `KSJTestToken` has an unrestricted faucet and is intentionally worthless; use only on a test network. The frontend offers wallet-driven deployment on Sepolia.

## Verification

```sh
git submodule update --init lib/openzeppelin-contracts
FOUNDRY_PROFILE=ksj forge test -vv
FOUNDRY_PROFILE=ksj forge build
```

The `ksj` Foundry profile isolates this version from legacy contracts/tests. Ten tests cover all four slots, payment, double-sale prevention, stale-price rejection, failed transfer rollback, owner-only operations and refunds.

## Hardware boundary

Purchased means payment, not delivery. The frontend verifies the receipt separately before issuing one BLE command. The generic supplied KSJ protocol does not provide purchase-bound authorization. A browser and local storage are not a trusted enforcement layer: this is a supervised field pilot, not an unattended commercial machine. Physical tests, trusted-controller/global-replay protection and a hardware security review remain required before valuable stock / real payments. The supplied protocol's twelve channels do not imply twelve physical compartments.
