from brownie import *
from brownie import convert
from brownie.convert import EthAddress
from eth_account.messages import encode_defunct
from eth_account import Account
from pathlib import Path

import time
import pytest
import eth_abi
import hashlib

def main():
    deps = project.load(  Path.home() / ".brownie" / "packages" / config["dependencies"][0])
    TransparentUpgradeableProxy = deps.TransparentUpgradeableProxy
    owner = accounts[0]
    deployer = accounts[1]
    if chain.id == 1:
        ethDepositContract = "0x00000000219ab540356cbb839cbe05303d7705fa"
    elif chain.id == 5:
        ethDepositContract = "0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b"
    else:
        assert False

    print(f'contract owner account: {owner.address}\n')


    # signer privkey
    signerPub = "0x2C4594B11BaAD822B5be6a65348779Bb97473682"
    signerPrivate = "a441e60dd489bdfa4a848bee22d9225a6d53f4aadad492ccae5014e1d88d84cc"

    # staker info prepare
    pubkey = 0x99380e442ac9955cd0b82a820f4d2b5a630cc0b24fa57f1d0f80dd42fcc1be92ac4038b29de057e9b62c7783103651f9
    claimAddr = owner.address
    withdrawAddr = "0x11ad6f6224eaad9a75f5985dd5cbe5c28187e1b7"
    signature = 0xa2f1845644cee06469cea42dbd5ebf4505b9489ed896788ab2b8e42124aceb88a6565a375546254f5507b425d15c90a10e772708dbe9a56b3e46f5c47e8aaf6a9849ae4f838bb9bac068bcde47b616fd2b0824de23ec17981987668a4c50e17d
    md = digest(claimAddr, withdrawAddr, pubkey, signature)

    print("Digest:", md.hexdigest())

    # sign digest in EIP-191 standard
    message = encode_defunct(md.digest())
    print("Message:", message)
    signed_message = Account.sign_message(message, private_key=signerPrivate)
    print("Signature:", signed_message)

    ### deploy reward pool
    rewardpool_contract = RewardPool.deploy(
            {'from': deployer}
            )

    rewardpool_proxy = TransparentUpgradeableProxy.deploy(
            rewardpool_contract, deployer, b'',
            {'from': deployer}
            )

    transparent_rewardpool= Contract.from_abi("RewardPool", rewardpool_proxy.address, RewardPool.abi)
    print("RewardPool address:", transparent_rewardpool)

    ### deploy staking contract
    direct_staking_contract = DirectStaking.deploy(
            {'from': deployer}
            )

    direct_staking_contract_proxy = TransparentUpgradeableProxy.deploy(
            direct_staking_contract, deployer, b'',
            {'from': deployer}
            )

    transparent_ds = Contract.from_abi("DirectStaking", direct_staking_contract_proxy.address, DirectStaking.abi)
    print("DirectStaking address:", transparent_ds)


    # init
    transparent_rewardpool.initialize(
            {'from': owner}
            )
    transparent_ds.initialize(
            {'from': owner}
            )
    
    #grant CONTROLLER ROLE to ds
    print("Granting Role Controller to:", transparent_ds)
    transparent_rewardpool.grantRole(transparent_rewardpool.CONTROLLER_ROLE(), transparent_ds, {'from': owner})

    transparent_ds.setETHDepositContract(ethDepositContract, {'from': owner})
    transparent_ds.setRewardPool(transparent_rewardpool, {'from': owner})
    transparent_ds.setSigner(signerPub, {'from': owner})

     #stake
    print("stake 32 ETH")
    # ecrecover in Solidity expects the signature to be split into v as a uint8,
    #   and r, s as a bytes32
    # Remix / web3.js expect r and s to be encoded to hex
    print(signed_message.signature, bytes(signed_message.signature))
    transparent_ds.stake(claimAddr, withdrawAddr, [pubkey], [signature], bytes(signed_message.signature), 1,0,{"from":owner, 'value': '32 ether'})

    # test
    print("transfer 0.1 eth")
    owner.transfer(transparent_rewardpool.address, '0.1 ethers')

    print("getPendingReward:", transparent_rewardpool.getPendingReward(owner))
    print("getPendingManagerRevenue:", transparent_rewardpool.getPendingManagerRevenue())
    print("updateReward:")
    transparent_rewardpool.updateReward({'from':owner})
    print("getPendingReward:", transparent_rewardpool.getPendingReward(owner))
    print("balance before claimReward:", transparent_rewardpool.balance())
    transparent_rewardpool.claimRewards(owner, transparent_rewardpool.getPendingReward(owner), {'from':owner})
    print("getPendingReward:", transparent_rewardpool.getPendingReward(owner))
    print("balance after claimReward:", transparent_rewardpool.balance())
    print("getPendingManagerRevenue:", transparent_rewardpool.getPendingManagerRevenue())
    print("withdrawManagerRevenue:",transparent_rewardpool.withdrawManagerRevenue(20000000000000000,owner, {'from':owner}))
    print("getPendingManagerRevenue:", transparent_rewardpool.getPendingManagerRevenue())
    print("getAccountedBalance:", transparent_rewardpool.getAccountedBalance())
    print("exit")
    transparent_ds.exit(0, {"from":owner})
    print("getPendingReward:", transparent_rewardpool.getPendingReward(owner))
    print("transfer 0.1 eth")
    owner.transfer(transparent_rewardpool.address, '0.1 ethers')
    print("getPendingReward:", transparent_rewardpool.getPendingReward(owner))
    print("getExitQueueLength:", transparent_ds.getExitQueueLength())
    print("getExitQueue(0,1):", transparent_ds.getExitQueue(0,1))

def digest(claimaddr, withdrawaddr, pubkey, signature):
    #print(EthAddress(claimaddr))
    abi = eth_abi.encode_abi(['address', 'address'], [claimaddr, convert.to_address(withdrawaddr)])
    digest = hashlib.sha256(abi)
    abi = eth_abi.encode_abi(['bytes32', 'bytes', 'bytes'], [convert.to_bytes(digest.hexdigest(),"bytes32"), convert.to_bytes(pubkey,"bytes"), convert.to_bytes(signature,"bytes")])
    digest = hashlib.sha256(abi)
    return digest

