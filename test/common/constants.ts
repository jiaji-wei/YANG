import bn from 'bignumber.js';
import { BigNumberish, BigNumber } from 'ethers';


bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

export const MAX_GAS_LIMIT = 12_450_000;
export const BN = BigNumber.from;
export const BNe = (n: BigNumberish, exponent: BigNumberish) => BN(n).mul(BN(10).pow(exponent));
export const BNe18 = (n: BigNumberish) => BNe(n, 18);
export const MaxUint128 = BigNumber.from(2).pow(128).sub(1)
export const ZeroAddress = '0x0000000000000000000000000000000000000000'
export const USDCAddress = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
export const USDTAddress = '0xdAC17F958D2ee523a2206206994597C13D831ec7'
export const UniswapV3FactoryAddress = '0x1F98431c8aD98523631AE4a59f267346ea31F984';

export const MIN_SQRT_RATIO = BigNumber.from('4295128739')
export const MAX_SQRT_RATIO = BigNumber.from('1461446703485210103287273052203988822378723970342')
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
