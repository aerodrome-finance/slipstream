import { BigNumber } from 'ethers'

export const MaxUint128 = BigNumber.from(2).pow(128).sub(1)

export const V2_PLACEHOLDER_VOLATILE = 4194304 // 1 << 22
export const V2_PLACEHOLDER_STABLE = 2097152 // 1 << 21
export const V3_PLACEHOLDER_CANONICAL = 1048576 // 1 << 20

export enum FeeAmount {
  LOW = 500,
  MEDIUM = 3000,
  HIGH = 10000,
}

export const TICK_SPACINGS: { [amount in FeeAmount]: number } = {
  [FeeAmount.LOW]: 10,
  [FeeAmount.MEDIUM]: 60,
  [FeeAmount.HIGH]: 200,
}

export const CANONICAL_TICK_SPACINGS: { [amount in FeeAmount]: number } = {
  [FeeAmount.LOW]: 10 | V3_PLACEHOLDER_CANONICAL,
  [FeeAmount.MEDIUM]: 60 | V3_PLACEHOLDER_CANONICAL,
  [FeeAmount.HIGH]: 200 | V3_PLACEHOLDER_CANONICAL,
}
