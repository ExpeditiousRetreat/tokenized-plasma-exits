# Tokenized Plasma Exits


We've taken the Omise Go implementation of [Minimum Viable Plasma](https://ethresear.ch/t/minimal-viable-plasma/426) and tokenized the exit mechanism.  Rather than parties have to wait 7 to 14 days to withdraw their money, they recieve a token representing this payout.  They can now sell this withdrawal token as they would any ERC20 token.  After the wait period is complete, the owner of the token can withdraw the collateral from the plasma root_chain contract. This repository represents a work in progress and will undergo large-scale modifications as requirements change.

## Overview

Plasma MVP is split into four main parts: `root_chain`, `child_chain`, `client`, and `cli`. All chainges to the OMG implementation are made in the 'root_chain' section.  

## Security Implications

Plasma implementations suffer from two major concerns:  usability and security.  Our Tokenized Plasma Exit (TPE) implementation addresses both of these problems.  

### Usability

Needing to wait seven days for a withdrawal is a UX nightmare.  It severly limits the ability of participants to quickly move in and out of plasma chains and exposes users to extreme price risk considerations due to the volatility of the unaccessable collateral.  By tokenizing the withdrawal, we envision a DEX that can be used to immediately sell your withdrawals for a value extremely close to the withdraw amount. 

### Security

Incentivizing individuals to monitor and store data related to the plasma chain is a problem that has yet been solved.  Individuals wanting to transact on the plasma chain do not want the overhead of storing all plasma chain data and third parties have no incentive to monitor or challenge problematic exits from the plasma chain.  

By creating a market out of the withdrawals, third parties looking to purchase plasma exit tokens are incentivized to monitor the plasma chain to ensure that the tokens they are purchasing 

## Structure

Each withdrawal is issued a new token (a new TPE token with a unique address).  This is done since each token is fungible with itself (fractions) however not fungible with other withdrawals (different risk profiles). 

The tokens are standard ERC20 tokens.

## Economics

The tokens created by the TPE will have a value relative to the security of each individual withdrawal.  If the withdrawal is invalid, the tokens will be worthless, so the tokens themselves represent the individual validity of each participants withdrawal.  

The TPE token value should represent:

	t) The time preference of individuals withdraing

	f) discounted future value of the collateral

	r) risk associated with asymetric information surrounding withdrawal ( How easily can the token withdrawal be validated by external parties )

    TPE_V = f(t, f, r)
 

## Notes

[OMG Plasm](https://github.com/omisego/plasma-mvp)

This project was started at ETHSanFransisco on Oct 5th, 2018.  

The team for developing this code is as follows:

Nicholas Fett

Bijan 

Jeff

Eddy 

