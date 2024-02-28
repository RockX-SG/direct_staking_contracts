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
   
    me = accounts.at('0x75fE76d459e8ca4440822f7D90aa56a222726EB6', {'force':True})
    accounts[0].transfer(me, '10 ether')
    for x in range(130):
        me.transfer(me, 0)

    #TransparentUpgradeableProxy.deploy('0x62cea417a02cac2433df622fe3a0eb0662f1ca61', me, b'', {'from':me})
