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
    deployer = accounts.load('goerli-deployer')
    ### deploy staking contract
    direct_staking_contract = DirectStaking.deploy(
            {'from': deployer}, publish_source=True

            )
