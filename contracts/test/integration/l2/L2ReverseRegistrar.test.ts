import { shouldSupportInterfaces } from '@ensdomains/hardhat-chai-matchers-viem/behaviour'
import hre from 'hardhat'
import {
  decodeFunctionResult,
  encodeFunctionData,
  getAddress,
  namehash,
  serializeErc6492Signature,
  type Address
} from 'viem'
import { optimism } from 'viem/chains'
import { describe, expect, it } from 'vitest'
import { dnsEncodeName } from '../../utils/utils.ts'
import { deployUniversalSigValidator } from '../fixtures/deployUniversalSigValidator.ts'

const connection = await hre.network.connect()

// Chain ID for Optimism - used to construct coin type
const OPTIMISM_CHAIN_ID = BigInt(optimism.id)
// Coin type format: 0x80000000 | chainId (see ENSIP-11)
const COIN_TYPE = 0x80000000n | OPTIMISM_CHAIN_ID
// Label is the hex representation of the coin type
const COIN_TYPE_LABEL = COIN_TYPE.toString(16)
// `8000000a.reverse`
const PARENT_NAMESPACE = `${COIN_TYPE_LABEL}.reverse`

/**
 * Converts a Unix timestamp to ISO 8601 format (matching LibISO8601.sol)
 * Format: YYYY-MM-DDTHH:MM:SSZ
 */
function timestampToISO8601(timestamp: bigint): string {
  const date = new Date(Number(timestamp) * 1000)
  return date.toISOString().replace('.000Z', 'Z')
}

/**
 * Creates the plaintext message for setNameForAddrWithSignature
 * This must match the format in L2ReverseRegistrar._createNameForAddrWithSignatureMessageHash
 */
function createNameForAddrMessage({
  name,
  address,
  chainIds,
  expirationTime,
  validatorAddress,
  nonce,
}: {
  name: string
  address: Address
  chainIds: bigint[]
  expirationTime: bigint
  validatorAddress: Address
  nonce: bigint
}): string {
  const chainIdsString = chainIds.map((id) => id.toString()).join(', ')
  const expiresAtString = timestampToISO8601(expirationTime)
  const nonceString = nonce.toString()

  return `You are setting your ENS primary name to:
${name}

Address: ${getAddress(address)}
Chains: ${chainIdsString}
Expires At: ${expiresAtString}

---
Validator: ${getAddress(validatorAddress)}
Nonce: ${nonceString}`
}

/**
 * Creates the plaintext message for setNameForOwnableWithSignature
 * This must match the format in L2ReverseRegistrar._createNameForOwnableWithSignatureMessageHash
 */
function createNameForOwnableMessage({
  name,
  contractAddress,
  owner,
  chainIds,
  expirationTime,
  validatorAddress,
  nonce,
}: {
  name: string
  contractAddress: Address
  owner: Address
  chainIds: bigint[]
  expirationTime: bigint
  validatorAddress: Address
  nonce: bigint
}): string {
  const chainIdsString = chainIds.map((id) => id.toString()).join(', ')
  const expiresAtString = timestampToISO8601(expirationTime)
  const nonceString = nonce.toString()

  return `You are setting the ENS primary name for a contract you own to:
${name}

Contract Address: ${getAddress(contractAddress)}
Owner: ${getAddress(owner)}
Chains: ${chainIdsString}
Expires At: ${expiresAtString}

---
Validator: ${getAddress(validatorAddress)}
Nonce: ${nonceString}`
}

async function fixture() {
  const accounts = await connection.viem
    .getWalletClients()
    .then((clients) => clients.map((c) => c.account))

  await deployUniversalSigValidator(connection)

  const l2ReverseRegistrar = await connection.viem.deployContract(
    // Use fully qualified name to ensure the correct contract is deployed
    'src/L2/reverse-registrar/L2ReverseRegistrar.sol:L2ReverseRegistrar',
    [COIN_TYPE, COIN_TYPE_LABEL],
  )
  const mockSmartContractAccount = await connection.viem.deployContract(
    'MockSmartContractWallet',
    [accounts[0].address],
  )
  const mockOwnableSca = await connection.viem.deployContract('MockOwnable', [
    mockSmartContractAccount.address,
  ])
  const mockErc6492WalletFactory = await connection.viem.deployContract(
    'MockERC6492WalletFactory',
  )
  const mockOwnableEoa = await connection.viem.deployContract('MockOwnable', [
    accounts[0].address,
  ])

  /**
   * Helper function to get the name for an address
   * Since v2 uses name(bytes32 node) instead of nameForAddr(address)
   */
  async function getNameForAddr(addr: Address): Promise<string> {
    const node = namehash(`${addr.slice(2).toLowerCase()}.${PARENT_NAMESPACE}`)
    return l2ReverseRegistrar.read.name([node])
  }

  return {
    l2ReverseRegistrar,
    mockSmartContractAccount,
    mockErc6492WalletFactory,
    mockOwnableSca,
    mockOwnableEoa,
    accounts,
    getNameForAddr,
  }
}

const loadFixture = async () => connection.networkHelpers.loadFixture(fixture)

describe('L2ReverseRegistrar', () => {
  shouldSupportInterfaces({
    contract: () =>
      loadFixture().then(({ l2ReverseRegistrar }) => l2ReverseRegistrar),
    interfaces: [
      'src/L2/reverse-registrar/interfaces/IL2ReverseRegistrar.sol:IL2ReverseRegistrar',
      'IExtendedResolver',
      'INameResolver',
      'IERC165',
    ],
  })

  it('should deploy the contract', async () => {
    const { l2ReverseRegistrar } = await loadFixture()

    expect(l2ReverseRegistrar.address).not.toBeUndefined()
  })

  it('should have correct CHAIN_ID set', async () => {
    const { l2ReverseRegistrar } = await loadFixture()

    const chainId = await l2ReverseRegistrar.read.CHAIN_ID()
    expect(chainId).toStrictEqual(OPTIMISM_CHAIN_ID)
  })

  it('should have correct COIN_TYPE set', async () => {
    const { l2ReverseRegistrar } = await loadFixture()

    const coinType = await l2ReverseRegistrar.read.COIN_TYPE()
    expect(coinType).toStrictEqual(COIN_TYPE)
  })

  describe('setName', () => {
    async function setNameFixture() {
      const initial = await loadFixture()

      const name = 'myname.eth'

      return {
        ...initial,
        name,
      }
    }

    it('should set the name record for the calling account', async () => {
      const { l2ReverseRegistrar, name, accounts, getNameForAddr } =
        await connection.networkHelpers.loadFixture(setNameFixture)

      await l2ReverseRegistrar.write.setName([name])

      await expect(
        getNameForAddr(accounts[0].address),
      ).resolves.toStrictEqual(name)
    })

    it('event NameChanged is emitted', async () => {
      const { l2ReverseRegistrar, name } =
        await connection.networkHelpers.loadFixture(setNameFixture)

      await expect(l2ReverseRegistrar.write.setName([name])).toEmitEvent(
        'NameChanged',
      )
    })

    it('can update the name record', async () => {
      const { l2ReverseRegistrar, name, accounts, getNameForAddr } =
        await connection.networkHelpers.loadFixture(setNameFixture)

      await l2ReverseRegistrar.write.setName([name])
      const newName = 'newname.eth'
      await l2ReverseRegistrar.write.setName([newName])

      await expect(
        getNameForAddr(accounts[0].address),
      ).resolves.toStrictEqual(newName)
    })

    it('can set the name to an empty string', async () => {
      const { l2ReverseRegistrar, name, accounts, getNameForAddr } =
        await connection.networkHelpers.loadFixture(setNameFixture)

      await l2ReverseRegistrar.write.setName([name])
      await l2ReverseRegistrar.write.setName([''])

      await expect(
        getNameForAddr(accounts[0].address),
      ).resolves.toStrictEqual('')
    })
  })

  describe('setNameForAddr', () => {
    async function setNameForAddrFixture() {
      const initial = await loadFixture()

      const name = 'myname.eth'

      return {
        ...initial,
        name,
      }
    }

    it('should set the name record for a contract the caller owns', async () => {
      const { l2ReverseRegistrar, name, mockOwnableEoa, getNameForAddr } =
        await connection.networkHelpers.loadFixture(setNameForAddrFixture)

      await l2ReverseRegistrar.write.setNameForAddr([
        mockOwnableEoa.address,
        name,
      ])

      await expect(
        getNameForAddr(mockOwnableEoa.address),
      ).resolves.toStrictEqual(name)
    })

    it('event NameChanged is emitted', async () => {
      const { l2ReverseRegistrar, name, mockOwnableEoa } =
        await connection.networkHelpers.loadFixture(setNameForAddrFixture)

      await expect(
        l2ReverseRegistrar.write.setNameForAddr([mockOwnableEoa.address, name]),
      ).toEmitEvent('NameChanged')
    })

    it('caller can set their own name', async () => {
      const { l2ReverseRegistrar, name, accounts, getNameForAddr } =
        await connection.networkHelpers.loadFixture(setNameForAddrFixture)

      await l2ReverseRegistrar.write.setNameForAddr([
        accounts[0].address,
        name,
      ])

      await expect(
        getNameForAddr(accounts[0].address),
      ).resolves.toStrictEqual(name)
    })

    it('reverts if the caller is not the owner of the target address', async () => {
      const { l2ReverseRegistrar, name, accounts, mockOwnableEoa } =
        await connection.networkHelpers.loadFixture(setNameForAddrFixture)

      await expect(
        l2ReverseRegistrar.write.setNameForAddr(
          [mockOwnableEoa.address, name],
          {
            account: accounts[1],
          },
        ),
      ).toBeRevertedWithCustomError('Unauthorised')
    })

    it('reverts if caller tries to set name for another EOA', async () => {
      const { l2ReverseRegistrar, name, accounts } =
        await connection.networkHelpers.loadFixture(setNameForAddrFixture)

      await expect(
        l2ReverseRegistrar.write.setNameForAddr([accounts[1].address, name]),
      ).toBeRevertedWithCustomError('Unauthorised')
    })

    it('reverts if caller is not owner of the target contract (via Ownable)', async () => {
      const { l2ReverseRegistrar, name, accounts, mockOwnableSca } =
        await connection.networkHelpers.loadFixture(setNameForAddrFixture)

      // mockOwnableSca is owned by mockSmartContractAccount, not accounts[0]
      await expect(
        l2ReverseRegistrar.write.setNameForAddr([mockOwnableSca.address, name]),
      ).toBeRevertedWithCustomError('Unauthorised')
    })
  })

  describe('setNameForAddrWithSignature', () => {
    async function setNameForAddrWithSignatureFixture() {
      const initial = await loadFixture()
      const { l2ReverseRegistrar, accounts } = initial

      const name = 'myname.eth'

      const publicClient = await connection.viem.getPublicClient()
      const blockTimestamp = await publicClient
        .getBlock()
        .then((b) => b.timestamp)
      const expirationTime = blockTimestamp + 3600n

      const [walletClient] = await connection.viem.getWalletClients()

      const nonce = 1n

      const message = createNameForAddrMessage({
        name,
        address: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      return {
        ...initial,
        name,
        expirationTime,
        signature,
        walletClient,
        nonce,
      }
    }

    it('allows an account to sign a message to allow a relayer to claim the address', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        signature,
        accounts,
        nonce,
        getNameForAddr,
      } = await connection.networkHelpers.loadFixture(
        setNameForAddrWithSignatureFixture,
      )

      const claim = {
        name,
        addr: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce,
      }

      await expect(l2ReverseRegistrar.write.setNameForAddrWithSignature(
        [claim, signature],
        { account: accounts[1] },
      )).not.toBeReverted()

      await expect(
        getNameForAddr(accounts[0].address),
      ).resolves.toStrictEqual(name)
    })

    it('event NameChanged is emitted', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        signature,
        accounts,
        nonce,
      } = await connection.networkHelpers.loadFixture(
        setNameForAddrWithSignatureFixture,
      )

      const claim = {
        name,
        addr: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForAddrWithSignature(
          [claim, signature],
          { account: accounts[1] },
        ),
      ).toEmitEvent('NameChanged')
    })

    it('allows SCA signatures (ERC1271)', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        accounts,
        mockSmartContractAccount,
        walletClient,
        nonce,
        getNameForAddr,
      } = await connection.networkHelpers.loadFixture(
        setNameForAddrWithSignatureFixture,
      )

      const message = createNameForAddrMessage({
        name,
        address: mockSmartContractAccount.address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: mockSmartContractAccount.address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForAddrWithSignature(
          [claim, signature],
          { account: accounts[1] },
        ),
      ).toEmitEvent('NameChanged')

      await expect(
        getNameForAddr(mockSmartContractAccount.address),
      ).resolves.toStrictEqual(name)
    })

    it('allows undeployed SCA signatures (ERC6492)', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        accounts,
        mockErc6492WalletFactory,
        walletClient,
        nonce,
        getNameForAddr,
      } = await connection.networkHelpers.loadFixture(
        setNameForAddrWithSignatureFixture,
      )

      const predictedAddress =
        await mockErc6492WalletFactory.read.predictAddress([
          accounts[0].address,
        ])

      const message = createNameForAddrMessage({
        name,
        address: predictedAddress,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })      

      const wrappedSignature = serializeErc6492Signature({
        address: mockErc6492WalletFactory.address,
        data: encodeFunctionData({
          abi: mockErc6492WalletFactory.abi,
          functionName: 'createWallet',
          args: [accounts[0].address],
        }),
        signature,
      })

      const claim = {
        name,
        addr: predictedAddress,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForAddrWithSignature(
          [claim, wrappedSignature],
          { account: accounts[1] },
        ),
      ).toEmitEvent('NameChanged')

      await expect(
        getNameForAddr(predictedAddress),
      ).resolves.toStrictEqual(name)
    })

    it('reverts if signature parameters do not match', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        accounts,
        walletClient,
        nonce,
      } = await connection.networkHelpers.loadFixture(
        setNameForAddrWithSignatureFixture,
      )

      // Sign with different name
      const message = createNameForAddrMessage({
        name: 'different.eth',
        address: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name, // Original name
        addr: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForAddrWithSignature(
          [claim, signature],
          { account: accounts[1] },
        ),
      ).toBeRevertedWithCustomError('InvalidSignature')
    })

    it('reverts if signature is expired', async () => {
      const { l2ReverseRegistrar, name, accounts, walletClient, nonce } =
        await connection.networkHelpers.loadFixture(
          setNameForAddrWithSignatureFixture,
        )

      const publicClient = await connection.viem.getPublicClient()
      const blockTimestamp = await publicClient
        .getBlock()
        .then((b) => b.timestamp)
      const expiredTime = blockTimestamp - 1n // Already expired

      const message = createNameForAddrMessage({
        name,
        address: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime: expiredTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime: expiredTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForAddrWithSignature(
          [claim, signature],
          { account: accounts[1] },
        ),
      ).toBeRevertedWithCustomError('SignatureExpired')
    })

    it('reverts if expiry date is too high (more than 1 hour)', async () => {
      const { l2ReverseRegistrar, name, accounts, walletClient, nonce } =
        await connection.networkHelpers.loadFixture(
          setNameForAddrWithSignatureFixture,
        )

      const publicClient = await connection.viem.getPublicClient()
      const blockTimestamp = await publicClient
        .getBlock()
        .then((b) => b.timestamp)
      const tooHighExpiry = blockTimestamp + 3602n // More than 1 hour

      const message = createNameForAddrMessage({
        name,
        address: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime: tooHighExpiry,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime: tooHighExpiry,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForAddrWithSignature(
          [claim, signature],
          { account: accounts[1] },
        ),
      ).toBeRevertedWithCustomError('SignatureExpiryTooHigh')
    })

    it('allows multiple chain IDs in array', async () => {
      const { l2ReverseRegistrar, name, expirationTime, accounts, walletClient, nonce, getNameForAddr } =
        await connection.networkHelpers.loadFixture(
          setNameForAddrWithSignatureFixture,
        )

      const chainIds = [1n, 42161n, OPTIMISM_CHAIN_ID, 8453n] // ETH, Arbitrum, Optimism, Base

      const message = createNameForAddrMessage({
        name,
        address: accounts[0].address,
        chainIds,
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: accounts[0].address,
        chainIds,
        expirationTime,
        nonce,
      }

      await l2ReverseRegistrar.write.setNameForAddrWithSignature(
        [claim, signature],
        { account: accounts[1] },
      )

      await expect(
        getNameForAddr(accounts[0].address),
      ).resolves.toStrictEqual(name)
    })

    it('reverts if current chain ID is not in array', async () => {
      const { l2ReverseRegistrar, name, expirationTime, accounts, walletClient, nonce } =
        await connection.networkHelpers.loadFixture(
          setNameForAddrWithSignatureFixture,
        )

      const chainIds = [1n, 42161n, 8453n] // ETH, Arbitrum, Base - NO Optimism

      const message = createNameForAddrMessage({
        name,
        address: accounts[0].address,
        chainIds,
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: accounts[0].address,
        chainIds,
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForAddrWithSignature(
          [claim, signature],
          { account: accounts[1] },
        ),
      ).toBeRevertedWithCustomError('CurrentChainNotFound')
    })

    it('reverts if chain ID array is empty', async () => {
      const { l2ReverseRegistrar, name, expirationTime, accounts, walletClient, nonce } =
        await connection.networkHelpers.loadFixture(
          setNameForAddrWithSignatureFixture,
        )

      const chainIds: bigint[] = []

      const message = createNameForAddrMessage({
        name,
        address: accounts[0].address,
        chainIds,
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: accounts[0].address,
        chainIds,
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForAddrWithSignature(
          [claim, signature],
          { account: accounts[1] },
        ),
      ).toBeRevertedWithCustomError('CurrentChainNotFound')
    })

    it('reverts if the same signature is used twice (replay protection)', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        signature,
        accounts,
        nonce,
      } = await connection.networkHelpers.loadFixture(
        setNameForAddrWithSignatureFixture,
      )

      const claim = {
        name,
        addr: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce,
      }

      // First call should succeed
      await l2ReverseRegistrar.write.setNameForAddrWithSignature(
        [claim, signature],
        { account: accounts[1] },
      )

      // Second call with same signature should fail
      await expect(
        l2ReverseRegistrar.write.setNameForAddrWithSignature(
          [claim, signature],
          { account: accounts[1] },
        ),
      ).toBeRevertedWithCustomError('NonceAlreadyUsed')
    })

    it('allows different signatures with different nonces for same address', async () => {
      const { l2ReverseRegistrar, name, expirationTime, accounts, walletClient, getNameForAddr } =
        await connection.networkHelpers.loadFixture(
          setNameForAddrWithSignatureFixture,
        )

      // First signature with nonce 1
      const message1 = createNameForAddrMessage({
        name,
        address: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce: 1n,
      })

      const signature1 = await walletClient.signMessage({
        message: message1,
      })

      const claim1 = {
        name,
        addr: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce: 1n,
      }

      await expect(l2ReverseRegistrar.write.setNameForAddrWithSignature(
        [claim1, signature1],
        { account: accounts[1] },
      )).not.toBeReverted()

      // Second signature with nonce 2 and different name
      const newName = 'updated.eth'
      const message2 = createNameForAddrMessage({
        name: newName,
        address: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce: 2n,
      })

      const signature2 = await walletClient.signMessage({
        message: message2,
      })

      const claim2 = {
        name: newName,
        addr: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce: 2n,
      }

      await expect(l2ReverseRegistrar.write.setNameForAddrWithSignature(
        [claim2, signature2],
        { account: accounts[1] },
      )).not.toBeReverted()

      await expect(
        getNameForAddr(accounts[0].address),
      ).resolves.toStrictEqual(newName)
    })

    it('reverts if signed by wrong account', async () => {
      const { l2ReverseRegistrar, name, expirationTime, accounts, nonce } =
        await connection.networkHelpers.loadFixture(
          setNameForAddrWithSignatureFixture,
        )

      const [, secondWalletClient] = await connection.viem.getWalletClients()

      // Sign with account[1] but claim is for account[0]
      const message = createNameForAddrMessage({
        name,
        address: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await secondWalletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForAddrWithSignature(
          [claim, signature],
          { account: accounts[2] },
        ),
      ).toBeRevertedWithCustomError('InvalidSignature')
    })
  })

  describe('setNameForOwnableWithSignature', () => {
    async function setNameForOwnableWithSignatureFixture() {
      const initial = await loadFixture()
      const { l2ReverseRegistrar } = initial

      const name = 'ownable.eth'

      const publicClient = await connection.viem.getPublicClient()
      const blockTimestamp = await publicClient
        .getBlock()
        .then((b) => b.timestamp)
      const expirationTime = blockTimestamp + 3600n

      const [walletClient] = await connection.viem.getWalletClients()

      const nonce = 1n

      return {
        ...initial,
        name,
        expirationTime,
        walletClient,
        nonce,
      }
    }

    it('allows an EOA to sign a message to claim the address of a contract it owns via Ownable', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        accounts,
        mockOwnableEoa,
        walletClient,
        nonce,
        getNameForAddr,
      } = await connection.networkHelpers.loadFixture(
        setNameForOwnableWithSignatureFixture,
      )

      const message = createNameForOwnableMessage({
        name,
        contractAddress: mockOwnableEoa.address,
        owner: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: mockOwnableEoa.address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForOwnableWithSignature(
          [claim, accounts[0].address, signature],
          { account: accounts[9] },
        ),
      ).toEmitEvent('NameChanged')

      await expect(
        getNameForAddr(mockOwnableEoa.address),
      ).resolves.toStrictEqual(name)
    })

    it('allows an SCA to sign a message to claim the address of a contract it owns via Ownable', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        accounts,
        mockOwnableSca,
        mockSmartContractAccount,
        walletClient,
        nonce,
        getNameForAddr,
      } = await connection.networkHelpers.loadFixture(
        setNameForOwnableWithSignatureFixture,
      )

      const message = createNameForOwnableMessage({
        name,
        contractAddress: mockOwnableSca.address,
        owner: mockSmartContractAccount.address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: mockOwnableSca.address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForOwnableWithSignature(
          [claim, mockSmartContractAccount.address, signature],
          { account: accounts[9] },
        ),
      ).toEmitEvent('NameChanged')

      await expect(
        getNameForAddr(mockOwnableSca.address),
      ).resolves.toStrictEqual(name)
    })

    it('reverts if the owner address is not the owner of the contract', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        accounts,
        mockOwnableEoa,
        nonce,
      } = await connection.networkHelpers.loadFixture(
        setNameForOwnableWithSignatureFixture,
      )

      const [, secondWalletClient] = await connection.viem.getWalletClients()

      // Sign with accounts[1] and claim they own mockOwnableEoa
      const message = createNameForOwnableMessage({
        name,
        contractAddress: mockOwnableEoa.address,
        owner: accounts[1].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await secondWalletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: mockOwnableEoa.address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForOwnableWithSignature(
          [claim, accounts[1].address, signature],
          { account: accounts[9] },
        ),
      ).toBeRevertedWithCustomError('NotOwnerOfContract')
    })

    it('reverts if the target address is not a contract (is an EOA)', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        accounts,
        walletClient,
        nonce,
      } = await connection.networkHelpers.loadFixture(
        setNameForOwnableWithSignatureFixture,
      )

      // Try to claim for EOA account[2] saying account[0] owns it
      const message = createNameForOwnableMessage({
        name,
        contractAddress: accounts[2].address,
        owner: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: accounts[2].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForOwnableWithSignature(
          [claim, accounts[0].address, signature],
          { account: accounts[9] },
        ),
      ).toBeRevertedWithCustomError('NotOwnerOfContract')
    })

    it('reverts if the target address does not implement Ownable', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        accounts,
        walletClient,
        nonce,
      } = await connection.networkHelpers.loadFixture(
        setNameForOwnableWithSignatureFixture,
      )

      // L2ReverseRegistrar itself does not implement Ownable
      const message = createNameForOwnableMessage({
        name,
        contractAddress: l2ReverseRegistrar.address,
        owner: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: l2ReverseRegistrar.address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForOwnableWithSignature(
          [claim, accounts[0].address, signature],
          { account: accounts[9] },
        ),
      ).toBeRevertedWithCustomError('NotOwnerOfContract')
    })

    it('reverts if the signature is invalid', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        accounts,
        mockOwnableEoa,
        walletClient,
        nonce,
      } = await connection.networkHelpers.loadFixture(
        setNameForOwnableWithSignatureFixture,
      )

      // Sign with different expiration time
      const message = createNameForOwnableMessage({
        name,
        contractAddress: mockOwnableEoa.address,
        owner: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime: expirationTime - 100n,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: mockOwnableEoa.address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime, // Original expiration time
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForOwnableWithSignature(
          [claim, accounts[0].address, signature],
          { account: accounts[9] },
        ),
      ).toBeRevertedWithCustomError('InvalidSignature')
    })

    it('reverts if expiry date has passed', async () => {
      const {
        l2ReverseRegistrar,
        name,
        accounts,
        mockOwnableEoa,
        walletClient,
        nonce,
      } = await connection.networkHelpers.loadFixture(
        setNameForOwnableWithSignatureFixture,
      )

      const publicClient = await connection.viem.getPublicClient()
      const blockTimestamp = await publicClient
        .getBlock()
        .then((b) => b.timestamp)
      const expiredTime = blockTimestamp - 1n

      const message = createNameForOwnableMessage({
        name,
        contractAddress: mockOwnableEoa.address,
        owner: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime: expiredTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: mockOwnableEoa.address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime: expiredTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForOwnableWithSignature(
          [claim, accounts[0].address, signature],
          { account: accounts[9] },
        ),
      ).toBeRevertedWithCustomError('SignatureExpired')
    })

    it('reverts if expiry date is too high', async () => {
      const {
        l2ReverseRegistrar,
        name,
        accounts,
        mockOwnableEoa,
        walletClient,
        nonce,
      } = await connection.networkHelpers.loadFixture(
        setNameForOwnableWithSignatureFixture,
      )

      const publicClient = await connection.viem.getPublicClient()
      const blockTimestamp = await publicClient
        .getBlock()
        .then((b) => b.timestamp)
      const tooHighExpiry = blockTimestamp + 3602n

      const message = createNameForOwnableMessage({
        name,
        contractAddress: mockOwnableEoa.address,
        owner: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime: tooHighExpiry,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: mockOwnableEoa.address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime: tooHighExpiry,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForOwnableWithSignature(
          [claim, accounts[0].address, signature],
          { account: accounts[9] },
        ),
      ).toBeRevertedWithCustomError('SignatureExpiryTooHigh')
    })

    it('allows multiple chain IDs in array', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        accounts,
        mockOwnableEoa,
        walletClient,
        nonce,
        getNameForAddr,
      } = await connection.networkHelpers.loadFixture(
        setNameForOwnableWithSignatureFixture,
      )

      const chainIds = [1n, 42161n, OPTIMISM_CHAIN_ID, 8453n]

      const message = createNameForOwnableMessage({
        name,
        contractAddress: mockOwnableEoa.address,
        owner: accounts[0].address,
        chainIds,
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: mockOwnableEoa.address,
        chainIds,
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForOwnableWithSignature(
          [claim, accounts[0].address, signature],
          { account: accounts[9] },
        ),
      ).toEmitEvent('NameChanged')

      await expect(
        getNameForAddr(mockOwnableEoa.address),
      ).resolves.toStrictEqual(name)
    })

    it('reverts if current chain ID is not in array', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        accounts,
        mockOwnableEoa,
        walletClient,
        nonce,
      } = await connection.networkHelpers.loadFixture(
        setNameForOwnableWithSignatureFixture,
      )

      const chainIds = [1n, 42161n, 8453n] // No Optimism

      const message = createNameForOwnableMessage({
        name,
        contractAddress: mockOwnableEoa.address,
        owner: accounts[0].address,
        chainIds,
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: mockOwnableEoa.address,
        chainIds,
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForOwnableWithSignature(
          [claim, accounts[0].address, signature],
          { account: accounts[9] },
        ),
      ).toBeRevertedWithCustomError('CurrentChainNotFound')
    })

    it('reverts if chain ID array is empty', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        accounts,
        mockOwnableEoa,
        walletClient,
        nonce,
      } = await connection.networkHelpers.loadFixture(
        setNameForOwnableWithSignatureFixture,
      )

      const chainIds: bigint[] = []

      const message = createNameForOwnableMessage({
        name,
        contractAddress: mockOwnableEoa.address,
        owner: accounts[0].address,
        chainIds,
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: mockOwnableEoa.address,
        chainIds,
        expirationTime,
        nonce,
      }

      await expect(
        l2ReverseRegistrar.write.setNameForOwnableWithSignature(
          [claim, accounts[0].address, signature],
          { account: accounts[9] },
        ),
      ).toBeRevertedWithCustomError('CurrentChainNotFound')
    })

    it('reverts if the same signature is used twice (replay protection)', async () => {
      const {
        l2ReverseRegistrar,
        name,
        expirationTime,
        accounts,
        mockOwnableEoa,
        walletClient,
        nonce,
      } = await connection.networkHelpers.loadFixture(
        setNameForOwnableWithSignatureFixture,
      )

      const message = createNameForOwnableMessage({
        name,
        contractAddress: mockOwnableEoa.address,
        owner: accounts[0].address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        validatorAddress: l2ReverseRegistrar.address,
        nonce,
      })

      const signature = await walletClient.signMessage({
        message,
      })

      const claim = {
        name,
        addr: mockOwnableEoa.address,
        chainIds: [OPTIMISM_CHAIN_ID],
        expirationTime,
        nonce,
      }

      // First call should succeed
      await expect(l2ReverseRegistrar.write.setNameForOwnableWithSignature(
        [claim, accounts[0].address, signature],
        { account: accounts[9] },
      )).not.toBeReverted()

      // Second call with same signature should fail
      await expect(
        l2ReverseRegistrar.write.setNameForOwnableWithSignature(
          [claim, accounts[0].address, signature],
          { account: accounts[9] },
        ),
      ).toBeRevertedWithCustomError('NonceAlreadyUsed')
    })
  })

  describe('name (reading reverse records)', () => {
    it('returns empty string for unset address', async () => {
      const { accounts, getNameForAddr } = await loadFixture()

      await expect(
        getNameForAddr(accounts[5].address),
      ).resolves.toStrictEqual('')
    })
  })

  describe('resolve', () => {
    async function resolveFixture() {
      const initial = await loadFixture()
      const { l2ReverseRegistrar, accounts } = initial

      const name = 'test.eth'
      await l2ReverseRegistrar.write.setName([name], {
        account: accounts[0],
      })

      return {
        ...initial,
        name,
      }
    }

    it('can resolve name for an address via resolve()', async () => {
      const { l2ReverseRegistrar, name, accounts } =
        await connection.networkHelpers.loadFixture(resolveFixture)

      const addressString = accounts[0].address.slice(2).toLowerCase()
      
      const coinTypeLabel = COIN_TYPE_LABEL
      const reverseLabel = 'reverse'
      const fullName = `${addressString}.${coinTypeLabel}.${reverseLabel}`

      const dnsEncodedName = dnsEncodeName(fullName)
      const node = namehash(fullName)
      const calldata = encodeFunctionData({
        abi: l2ReverseRegistrar.abi,
        functionName: 'name',
        args: [node],
      })
      
      const result = await l2ReverseRegistrar.read.resolve([dnsEncodedName, calldata])

      const resultName = decodeFunctionResult({
        abi: l2ReverseRegistrar.abi,
        functionName: 'name',
        data: result,
      })
      
      expect(resultName).toStrictEqual(name)
    })
  })
})
