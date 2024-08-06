# Audit-271122
This repo is intended to provide sample contracts for auditing purposes.

### The Pioneers of VCP NFT collection

The Pioneers collection is created to get the game access token of VCP Ecosystem.
The contract includes several sub-collections with their own parameters.
The collection is protected with the private IPFS.


##### PioneersCollection functions:
```
1 Mint (and all nested functions)
    1.1 Batch mint with Chainlink
    1.2 Internal supply checks
    1.3 Mint with VRF callback (_mint())
    1.4 Mint with whitelist
    1.5 Open mint
    1.6 Referral operation processing
    1.7 Mint by claimer
2 Internal boundaries check
```

##### ReferralProcessor functions:
```
1 processReferralOperation() (and Nested Functions)
    1.1 processReferralOperation()
    1.2 destributeFunds()
```
