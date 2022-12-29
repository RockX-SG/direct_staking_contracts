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
    transparent_rewardpool.joinpool(owner, '32 ether', {'from':owner})
    print("getTotalShare", transparent_rewardpool.getTotalShare())
    print("transfer 0.1 eth")
    owner.transfer(transparent_rewardpool.address, '0.1 ethers')
    print("getPendingReward:", transparent_rewardpool.getPendingReward(owner))
    print("getPendingManagerRevenue:", transparent_rewardpool.getPendingManagerRevenue())
    print("updateReward:")
    transparent_rewardpool.updateReward({'from':owner})
    print("getPendingReward:", transparent_rewardpool.getPendingReward(owner))
    print("balance before claimReward:", transparent_rewardpool.balance())
    transparent_rewardpool.claimRewards(owner, 80000000000000000, {'from':owner})
    print("balance after claimReward:", transparent_rewardpool.balance())
    print("getPendingManagerRevenue:", transparent_rewardpool.getPendingManagerRevenue())
    print("withdrawManagerRevenue:",transparent_rewardpool.withdrawManagerRevenue(20000000000000000,owner, {'from':owner}))
    print("getPendingManagerRevenue:", transparent_rewardpool.getPendingManagerRevenue())
    print("getAccountedBalance:", transparent_rewardpool.getAccountedBalance())

