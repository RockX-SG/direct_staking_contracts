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

    # register 
    print("getNextValidatorToRegister", transparent_ds.getNextValidatorToRegister())
    print("getNextValidatorToBind", transparent_ds.getNextValidatorToBind())
    print("getNextValidatorToDeposit", transparent_ds.getNextValidatorToDeposit())
    

    print("register")
    transparent_ds.registerValidator(0x97d717d346868b9df4851684d5219f4deb4c7388ee1454c9b46837d29b40150ceeb5825d791f993b03745427b6cbe6db, {'from': owner})

    print("getNextValidatorToRegister", transparent_ds.getNextValidatorToRegister())
    print("getNextValidatorToBind", transparent_ds.getNextValidatorToBind())
    print("getNextValidatorToDeposit", transparent_ds.getNextValidatorToDeposit())
    
    #stake
    print("stake 32 ETH")
    transparent_ds.stake(owner, owner, 1, 0, time.time() + 600, {"from":owner, 'value': '32 ether'})

    print("getNextValidatorToRegister", transparent_ds.getNextValidatorToRegister())
    print("getNextValidatorToBind", transparent_ds.getNextValidatorToBind())
    print("getNextValidatorToDeposit", transparent_ds.getNextValidatorToDeposit())
    

    #batch Deposit
    print("batch deposit")
    transparent_ds.batchDeposit(0,  [0xa09b4dc28c10063f6e2a9d2ca94b23db029ef618660138898cb827eae227d99ee1c438988d0222ca4229ba85c40add3b045e823fdb7519a36538ff901ab89f311060bcecc517ba683b84009ee3509afbcd25e991ef34112a5a16be44265441eb], {"from":owner})

    print("getNextValidatorToRegister", transparent_ds.getNextValidatorToRegister())
    print("getNextValidatorToBind", transparent_ds.getNextValidatorToBind())
    print("getNextValidatorToDeposit", transparent_ds.getNextValidatorToDeposit())
    
    # test
    print("transfer 0.1 eth")
    owner.transfer(transparent_rewardpool.address, '0.1 ethers')

    print("getPendingReward:", transparent_rewardpool.getPendingReward(owner))
    print("getPendingManagerRevenue:", transparent_rewardpool.getPendingManagerRevenue())
    print("updateReward:")
    transparent_rewardpool.updateReward({'from':owner})
    print("getPendingReward:", transparent_rewardpool.getPendingReward(owner))
    print("balance before claimReward:", transparent_rewardpool.balance())
    transparent_rewardpool.claimRewards(owner, 80000000000000000, {'from':owner})
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
