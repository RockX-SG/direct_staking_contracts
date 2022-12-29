from brownie import *
from pathlib import Path

import time
import pytest

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

    rewardpool_contract = RewardPool.deploy(
            {'from': deployer}
            )

    rewardpool_proxy = TransparentUpgradeableProxy.deploy(
            rewardpool_contract, deployer, b'',
            {'from': deployer}
            )

    transparent_rewardpool= Contract.from_abi("RewardPool", rewardpool_proxy.address, RewardPool.abi)

    print("RewardPool address:", transparent_rewardpool)

    transparent_rewardpool.initialize(
            {'from': owner}
            )
    transparent_rewardpool.setManagerFeeShare(200, {'from':owner})
