import { ethers } from 'ethers'
import * as dotenv from 'dotenv'
import * as path from 'path'
import * as fs from 'fs'

// Load environment variables
dotenv.config()

// Interfaces
interface ICLFactory {
  allPoolsLength(): Promise<bigint>
  allPools(index: number): Promise<string>
  swapFeeModule(): Promise<string>
}

interface ICustomFeeModule {
  customFee(poolAddress: string): Promise<bigint>
}

// ABIs
const factoryAbi = [
  'function allPoolsLength() external view returns (uint256)',
  'function allPools(uint256) external view returns (address)',
  'function swapFeeModule() external view returns (address)',
]

const poolAbi = [
  'function token0() external view returns (address)',
  'function token1() external view returns (address)',
  'function tickSpacing() external view returns (int24)',
  'function fee() external view returns (uint24)',
]

const customFeeModuleAbi = ['function customFee(address pool) external view returns (uint24)']

const erc20Abi = ['function symbol() external view returns (string)']

/// @dev Helper to fetch Pools with custom fees
async function fetchCustomFees(
  provider: ethers.providers.Provider,
  factoryAddress: string
): Promise<{ pools: string[]; fees: bigint[] }> {
  const poolsFetched: string[] = []
  const feesFetched: bigint[] = []

  // Create contract instances
  const factory = (new ethers.Contract(factoryAddress, factoryAbi, provider) as unknown) as ICLFactory

  // Get the fee module address
  const feeModuleAddress = await factory.swapFeeModule()
  const feeModule = (new ethers.Contract(feeModuleAddress, customFeeModuleAbi, provider) as unknown) as ICustomFeeModule

  // Get total number of pools
  const length = await factory.allPoolsLength()

  // Iterate through all pools
  for (let i = 0; i < length; i++) {
    const poolAddress = await factory.allPools(i)
    const customFee: bigint = await feeModule.customFee(poolAddress)

    if (BigInt(customFee) !== BigInt(0)) {
      poolsFetched.push(poolAddress)
      feesFetched.push(customFee)
    }
  }

  console.log('=======================================')
  console.log('Total pool length:', length.toString())
  console.log('Pools with Custom Fees:', poolsFetched.length)
  console.log('=======================================')

  return { pools: poolsFetched, fees: feesFetched }
}

async function main() {
  // Set up provider and contract addresses
  const rpcUrl = process.env.BASE_RPC_URL
  if (!rpcUrl) {
    throw new Error('BASE_RPC_URL environment variable is not set')
  }

  const provider = new ethers.providers.JsonRpcProvider(rpcUrl)
  const factoryAddress = '0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A'

  // Fetch pools with custom fees
  const { pools: poolsWithCustomFees, fees: customFees } = await fetchCustomFees(provider, factoryAddress)
  let poolIds: string[] = []

  // Print details for each pool
  console.log('\nDetails for pools with custom fees:')
  console.log('=======================================')

  for (let i = 0; i < poolsWithCustomFees.length; i++) {
    const poolAddress = poolsWithCustomFees[i]
    const customFee = customFees[i]

    const pool = new ethers.Contract(poolAddress, poolAbi, provider)
    const token0 = await pool.token0()
    const token1 = await pool.token1()
    const tickSpacing = await pool.tickSpacing()

    // Get token symbols
    const token0Contract = new ethers.Contract(token0, erc20Abi, provider)
    const token1Contract = new ethers.Contract(token1, erc20Abi, provider)
    const token0Symbol = await token0Contract.symbol()
    const token1Symbol = await token1Contract.symbol()

    const poolId = `CL${tickSpacing}-${token0Symbol}/${token1Symbol} ${Number(customFee) / 10_000}%`
    poolIds.push(poolId)

    console.log('Pool Address:', poolAddress)
    console.log('Custom Fee: ', customFee)
    console.log(poolId)
    console.log('---------------------------------------')
  }

  console.log('=======================================')
  console.log('Pools with Custom Fees:', poolsWithCustomFees.length)
  console.log('=======================================')

  // Create logs directory if it doesn't exist
  const logsDir = path.join(process.cwd(), 'logs')
  if (!fs.existsSync(logsDir)) {
    fs.mkdirSync(logsDir)
  }

  // Log custom fees & pool addresses to dynamicFees.json
  const jsonData = {
    pools: poolsWithCustomFees,
    customFees: customFees,
  }

  // Log pool information to info.json
  const infoData = poolsWithCustomFees.map((address, index) => ({
    info: poolIds[index],
    address,
    customFee: customFees[index],
  }))

  // Write to JSON files
  const jsonPath = path.join(logsDir, 'dynamicFees.json')
  const infoPath = path.join(logsDir, 'info.json')

  fs.writeFileSync(jsonPath, JSON.stringify(jsonData, null, 2))
  fs.writeFileSync(infoPath, JSON.stringify(infoData, null, 2))

  console.log('\nLogs written to logs/dynamicFees.json')
  console.log('Pool info written to logs/info.json')
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
