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
    ProxyAdmin = deps.ProxyAdmin

    gnosis_safe = accounts.at('0xAeE017052DF6Ac002647229D58B786E380B9721A', {'force':True})
    proxy_admin_contract = ProxyAdmin.at('0xa5F2B6AB5B38b88Ba221741b3A189999b4c889C6')
    direct_staking_proxy = '0xe8239B17034c372CDF8A5F8d3cCb7Cf1795c4572'
    deployer = accounts.load('mainnet-deployer')

    ### deploy staking contract
    direct_staking_contract = DirectStaking.deploy(
            {'from': deployer})

    proxy_admin_contract.upgrade(direct_staking_proxy, direct_staking_contract, {'from': gnosis_safe})
    transparent_direct_staking = Contract.from_abi("DirectStaking", direct_staking_proxy, DirectStaking.abi)

    ### invoke some methods
    print(transparent_direct_staking.DEPOSIT_SIZE())
    print(transparent_direct_staking.getExitQueueLength())
    #print(rewardpool_contract.CONTROLLER_ROLE())
