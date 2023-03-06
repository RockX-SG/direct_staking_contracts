from brownie import *
from pathlib import Path

import time
import pytest

def main():
    deps = project.load(  Path.home() / ".brownie" / "packages" / config["dependencies"][0])
    TransparentUpgradeableProxy = deps.TransparentUpgradeableProxy

    owner = accounts[0]
    deployer = accounts[1]

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
    print("getPendingReward:", transparent_rewardpool.getPendingReward(owner))
    print("balance():", transparent_rewardpool.balance())
    print("claimRewards:",transparent_rewardpool.claimRewards(owner, 80000000000000000, {'from':owner}))
    print("getPendingReward:", transparent_rewardpool.getPendingReward(owner))
    print("balance():", transparent_rewardpool.balance())
    print("getPendingManagerRevenue:", transparent_rewardpool.getPendingManagerRevenue())
    print("withdrawManagerRevenue:",transparent_rewardpool.withdrawManagerRevenue(20000000000000000,owner, {'from':owner}))
    print("getPendingManagerRevenue:", transparent_rewardpool.getPendingManagerRevenue())
    print("getAccountedBalance:", transparent_rewardpool.getAccountedBalance())

