# Slipstream

This repository contains the smart contracts for the Slipstream Concentrated Liquidity contracts. It contains
the core concentrated liquidity contracts, adapted from UniswapV3's core contracts. It contains the higher level
periphery contracts, adapted from UniswapV3's periphery contracts. It also contains gauges designed to operate
within the Velodrome ecosystem.  

See `SPECIFICATION.md` and `CHANGELOG.md` for more information. 

## Installation

This repository is a hybrid hardhat and foundry repository.

Install hardhat dependencies with `yarn install`.
Install foundry dependencies with `forge install`.

Run hardhat tests with `yarn test`.
Run forge tests with `forge test`.

## Testing

### Invariants

To run the invariant tests, echidna must be installed. The following instructions require additional installations (e.g. of solc-select). 

```
echidna test/invariants/E2E_mint_burn.sol --config test/invariants/E2E_mint_burn.config.yaml --contract E2E_mint_burn
echidna test/invariants/E2E_swap.sol --config test/invariants/E2E_swap.config.yaml --contract E2E_swap
```

## Licensing

As this repository depends on the UniswapV3 `v3-core` and `v3-periphery` repository, the contracts in the 
`contracts/core` and  `contracts/periphery` folders are licensed under `GPL-2.0-or-later` or alternative 
licenses (as indicated in their SPDX headers).

Files in the `contracts/gauge` folder are licensed under the Business Source License 1.1 (`BUSL-1.1`).

## Bug Bounty
Velodrome has a live bug bounty hosted on ([Immunefi](https://immunefi.com/bounty/velodromefinance/)).

## Deployment

| Name               | Address                                                                                                                               |
| :----------------- | :------------------------------------------------------------------------------------------------------------------------------------ |
| GaugeFactory               | [0xD30677bd8dd15132F251Cb54CbDA552d2A05Fb08](https://basescan.org/address/0xD30677bd8dd15132F251Cb54CbDA552d2A05Fb08#code) |
| GaugeImplementation               | [0xF5601F95708256A118EF5971820327F362442D2d](https://basescan.org/address/0xF5601F95708256A118EF5971820327F362442D2d#code) |
| MixedQuoter               | [0x0A5aA5D3a4d28014f967Bf0f29EAA3FF9807D5c6](https://basescan.org/address/0x0A5aA5D3a4d28014f967Bf0f29EAA3FF9807D5c6#code) |
| NonfungiblePositionManager               | [0x827922686190790b37229fd06084350E74485b72](https://basescan.org/address/0x827922686190790b37229fd06084350E74485b72#code) |
| NonfungibleTokenPositionDescriptor               | [0x01b0CaCB9A8004e08D075c919B5dF3b59FD53c55](https://basescan.org/address/0x01b0CaCB9A8004e08D075c919B5dF3b59FD53c55#code) |
| PoolFactory               | [0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A](https://basescan.org/address/0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A#code) |
| PoolImplementation               | [0xeC8E5342B19977B4eF8892e02D8DAEcfa1315831](https://basescan.org/address/0xeC8E5342B19977B4eF8892e02D8DAEcfa1315831#code) |
| QuoterV2               | [0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0](https://basescan.org/address/0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0#code) |
| CustomSwapFeeModule               | [0xF4171B0953b52Fa55462E4d76ecA1845Db69af00](https://basescan.org/address/0xF4171B0953b52Fa55462E4d76ecA1845Db69af00#code) |
| CustomUnstakedFeeModule               | [0x0AD08370c76Ff426F534bb2AFFD9b5555338ee68](https://basescan.org/address/0x0AD08370c76Ff426F534bb2AFFD9b5555338ee68#code) |
| SwapRouter               | [0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5](https://basescan.org/address/0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5#code) |
| SugarHelper               | [0x0AD09A66af0154a84e86F761313d02d0abB6edd5](https://basescan.org/address/0x0AD09A66af0154a84e86F761313d02d0abB6edd5#code) |
| DynamicSwapFeeModule               | [0xDB45818A6db280ecfeB33cbeBd445423d0216b5D](https://basescan.org/address/0xDB45818A6db280ecfeB33cbeBd445423d0216b5D#code) |
