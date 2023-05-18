import pytest
import time
import sys
import brownie
import random
import eth_abi
import hashlib

from pathlib import Path
from brownie import convert
from brownie import *
from brownie.convert import EthAddress
from brownie.network.state import Chain
from eth_account.messages import encode_defunct
from eth_account import Account
from pathlib import Path

""" test of emergency exit a validator"""
def test_emergencyExit(setup_contracts, owner, pubkeys, sigs, signerPrivate, withdraw_address):
    transparent_ds, transparent_rewardpool = setup_contracts
    claimAddr = owner.address

    ''' exit a non-existing validator should revert'''
    with brownie.reverts():
        transparent_ds.emergencyExit(0, True, {'from':owner})

    ''' non CONTROLLER ROLE initiates claimRewardsFor should revert '''
    with brownie.reverts():
        transparent_rewardpool.claimRewardsFor(claimAddr, {'from':accounts[9]})

    ''' sign digest in EIP-191 standard '''
    md = digest(0, transparent_ds.address, claimAddr, withdraw_address, pubkeys, sigs)
    message = encode_defunct(md.digest())
    signed_message = Account.sign_message(message, private_key=signerPrivate)
    transparent_ds.stake(claimAddr, withdraw_address, pubkeys, sigs, bytes(signed_message.signature), 0, 0, {"from":owner, 'value': '64 ether'})

    ''' Transfer 0.1 eth as MEV revenue '''
    owner.transfer(transparent_rewardpool.address, '0.1 ethers')

    ''' Initiating emergency exit '''
    balanceBeforeExit = owner.balance()
    mevRewards = transparent_rewardpool.getPendingReward(claimAddr)
    transparent_ds.emergencyExit(0, True, {'from':owner})

    assert owner.balance() == balanceBeforeExit + mevRewards
    assert transparent_rewardpool.getPendingReward(claimAddr) == 0 
   
    ''' emergencyExit again should revert '''
    with brownie.reverts("EXITING"):
        transparent_ds.emergencyExit(0, True, {'from':owner})

    with brownie.reverts("EXITING"):
        transparent_ds.emergencyExit(0, False, {'from':owner})

""" test of emergency exit a validator without mev rewards claiming"""
def test_emergencyExit2(setup_contracts, owner, pubkeys, sigs, signerPrivate, withdraw_address):
    transparent_ds, transparent_rewardpool = setup_contracts
    claimAddr = owner.address

    ''' sign digest in EIP-191 standard '''
    md = digest(0, transparent_ds.address, claimAddr, withdraw_address, pubkeys, sigs)
    message = encode_defunct(md.digest())
    signed_message = Account.sign_message(message, private_key=signerPrivate)
    transparent_ds.stake(claimAddr, withdraw_address, pubkeys, sigs, bytes(signed_message.signature), 0, 0, {"from":owner, 'value': '64 ether'})

    ''' Transfer 0.1 eth as MEV revenue '''
    owner.transfer(transparent_rewardpool.address, '0.1 ethers')

    ''' Initiating emergency exit '''
    balanceBeforeExit = owner.balance()
    mevRewards = transparent_rewardpool.getPendingReward(claimAddr)
    transparent_ds.emergencyExit(0, False, {'from':owner})

    assert owner.balance() == balanceBeforeExit
    assert transparent_rewardpool.getPendingReward(claimAddr) == mevRewards
   
    ''' emergencyExit again should revert '''
    with brownie.reverts("EXITING"):
        transparent_ds.emergencyExit(0, False, {'from':owner})

""" test of batch emergency validators """
def test_batchEmergencyExit(setup_contracts, owner, pubkeys, sigs, signerPrivate, withdraw_address):
    transparent_ds, transparent_rewardpool = setup_contracts
    claimAddr = owner.address

    ''' sign digest in EIP-191 standard '''
    md = digest(0, transparent_ds.address, claimAddr, withdraw_address, pubkeys, sigs)
    message = encode_defunct(md.digest())
    signed_message = Account.sign_message(message, private_key=signerPrivate)
    transparent_ds.stake(claimAddr, withdraw_address, pubkeys, sigs, bytes(signed_message.signature), 0, 0, {"from":owner, 'value': '64 ether'})

    ''' Transfer 0.1 eth as MEV revenue '''
    owner.transfer(transparent_rewardpool.address, '0.1 ethers')

    ''' Initiating emergency exit '''
    balanceBeforeExit = owner.balance()
    mevRewards = transparent_rewardpool.getPendingReward(claimAddr)
    transparent_ds.batchEmergencyExit([0,1], True, {'from':owner})

    assert owner.balance() == balanceBeforeExit + mevRewards
    assert transparent_rewardpool.getPendingReward(claimAddr) == 0 

    ''' emergencyExit again should revert '''
    with brownie.reverts("EXITING"):
        transparent_ds.batchEmergencyExit([0,1], True, {'from':owner})

    ''' emergencyExit again should revert '''
    with brownie.reverts("EXITING"):
        transparent_ds.emergencyExit(0, False, {'from':owner})

    ''' emergencyExit again should revert '''
    with brownie.reverts("EXITING"):
        transparent_ds.emergencyExit(1, False, {'from':owner})
   
def digest(extraData, contractAddr, claimaddr, withdrawaddr, pubkeys, signatures):
    #print(EthAddress(claimaddr))
    abi = eth_abi.encode(['uint256','address', 'uint256', 'address', 'address'], [extraData, contractAddr, Chain().id, claimaddr, convert.to_address(withdrawaddr)])
    digest = hashlib.sha256(abi)

    for i in range(len(pubkeys)):
        pubkey = pubkeys[i]
        signature = signatures[i]
        abi = eth_abi.encode(['bytes32', 'bytes', 'bytes'], [convert.to_bytes(digest.hexdigest(),"bytes32"), convert.to_bytes(pubkey,"bytes"), convert.to_bytes(signature,"bytes")])
        digest = hashlib.sha256(abi)

    return digest

