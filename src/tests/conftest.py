import pytest
import time
import sys

from pathlib import Path
from brownie import convert
from brownie import *

deps = project.load(  Path.home() / ".brownie" / "packages" / config["dependencies"][0])

@pytest.fixture
def owner():
    return accounts[0]

@pytest.fixture
def deployer():
    return accounts[1]

@pytest.fixture
def withdraw_address():
    return "0x11ad6f6224eaad9a75f5985dd5cbe5c28187e1b7"

# emulated signer 
@pytest.fixture
def signerPub():
    return "0x2C4594B11BaAD822B5be6a65348779Bb97473682"

@pytest.fixture
def signerPrivate():
    return "a441e60dd489bdfa4a848bee22d9225a6d53f4aadad492ccae5014e1d88d84cc"

@pytest.fixture
def pubkeys():
    return [0x99380e442ac9955cd0b82a820f4d2b5a630cc0b24fa57f1d0f80dd42fcc1be92ac4038b29de057e9b62c7783103651f9,
            0xae73a54c8206f664523e4a45f802c6b3b8f7bdb9a8c64f2af53bf7c4425e350c68cd906ec822e1ec84e8e3d626f958f3]

@pytest.fixture
def sigs():
    return [0xa2f1845644cee06469cea42dbd5ebf4505b9489ed896788ab2b8e42124aceb88a6565a375546254f5507b425d15c90a10e772708dbe9a56b3e46f5c47e8aaf6a9849ae4f838bb9bac068bcde47b616fd2b0824de23ec17981987668a4c50e17d,
            0xb337f858d1938704cdb2e5bf5dfb82723f7f5a08b6ce66200d24efa3973132dd3e701111cccf940c5965e80b5068af830be5e9d1ca1aa06e57ddd7b3948501f16e79c48e039738836ca4e5f3442b5e5c52eff472b4526a973649d0dad73698d5]

@pytest.fixture
def setup_contracts(owner, deployer, signerPub):
    chain.reset()
    TransparentUpgradeableProxy = deps.TransparentUpgradeableProxy
    if chain.id == 1:
        ethDepositContract = "0x00000000219ab540356cbb839cbe05303d7705fa"
    elif chain.id == 5:
        ethDepositContract = "0xff50ed3d0ec03aC01D4C79aAd74928BFF48a7b2b"
    else:
        assert False

    print(f'contract owner account: {owner.address}\n')

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
    transparent_ds.toggleShangHai({'from': owner})

    return transparent_ds, transparent_rewardpool
