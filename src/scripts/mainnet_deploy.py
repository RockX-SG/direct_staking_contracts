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

    owner = accounts.load('mainnet-owner')
    deployer = accounts.load('mainnet-deployer')

    if chain.id == 1:
        ethDepositContract = "0x00000000219ab540356cbb839cbe05303d7705fa"
    elif chain.id == 5:
        ethDepositContract = "0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b"
    else:
        assert False

    print(f'contract owner account: {owner.address}\n')


    ### deploy reward pool
    rewardpool_contract = RewardPool.deploy(
            {'from': deployer}, publish_source=True
            )

    rewardpool_proxy = TransparentUpgradeableProxy.deploy(
            rewardpool_contract, deployer, b'',
            {'from': deployer}, publish_source=True

            )

    transparent_rewardpool= Contract.from_abi("RewardPool", rewardpool_proxy.address, RewardPool.abi)
    print("RewardPool address:", transparent_rewardpool)

    ### deploy staking contract
    direct_staking_contract = DirectStaking.deploy(
            {'from': deployer}, publish_source=True

            )

    direct_staking_contract_proxy = TransparentUpgradeableProxy.deploy(
            direct_staking_contract, deployer, b'',
            {'from': deployer}, publish_source=True

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
