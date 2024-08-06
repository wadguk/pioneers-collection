import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { root, proof } from "../scripts/utils/merkleTree";
import type {
    PartnershipProcessor,
    PioneersCollection,
    PioneersCollection__factory,
    ReferralRegistry,
    VRFCoordinatorV2Mock,
} from "../typechain-types";

describe("PioneersCollection", () => {
    let CollectionContract: PioneersCollection__factory;
    let thePioneersCollection: PioneersCollection;
    let vrfCoordinatorV2: VRFCoordinatorV2Mock;
    let referralRegistry: ReferralRegistry;
    let partnershipProcessor: PartnershipProcessor;
    let owner: SignerWithAddress;
    let user: SignerWithAddress;
    let referree: SignerWithAddress;
    let incomeVault: SignerWithAddress;
    let referrerAddress: SignerWithAddress;
    const baseURL = `https://ipfs.io/ipfs/`;
    const baseCID = `bQmcgR5HMyWyptKvnB8hRF48yXMpW7fmYzaxTee3vHbz3G2`;
    const contractCID = `bQmcgR5HMyWyptKvnB8hRF48yXMpW7fmYzaxTee3vHbz3G2`;
    const defaultTokenCID = "bQmcgR5HMyWyptKvnB8hRF48yXMpW7fmYzaxTee3vHbz3G2";

    const mainSupply = 5;
    const goldSupply = 50;
    const availableMainSupply = 5;
    const mintFee = 250;
    const maxMintPerAddress = 5;
    const merkleMintWhitelistRoot = root;
    const keyHash = "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f";

    // Chainlink params
    const BASEFEE = ethers.utils.parseEther("1");
    const GASPRICELINK = 1000000000;

    before(async () => {
        [owner, user, referree, referrerAddress, incomeVault] = await ethers.getSigners();
        CollectionContract = (await ethers.getContractFactory(
            "PioneersCollection"
        )) as PioneersCollection__factory;
    });

    beforeEach(async () => {
        const VRFCoordinatorV2 = await ethers.getContractFactory("VRFCoordinatorV2Mock");
        vrfCoordinatorV2 = await VRFCoordinatorV2.deploy(BASEFEE, GASPRICELINK);
        const subscriptionTx = await vrfCoordinatorV2.createSubscription();
        const subscriptionTxReceipt = await subscriptionTx.wait();
        const subscriptionEvent = subscriptionTxReceipt.events?.find(
            (event) => event.event === "SubscriptionCreated"
        );
        const subscriptionId = subscriptionEvent?.args?.subId;
        await vrfCoordinatorV2.fundSubscription(
            subscriptionId,
            ethers.utils.parseEther("100")
        );

        const ReferralRegistry = await ethers.getContractFactory("ReferralRegistry");
        const PartnershipProcessor = await ethers.getContractFactory("PartnershipProcessor");

        referralRegistry = await ReferralRegistry.deploy();
        partnershipProcessor = await PartnershipProcessor.deploy(referralRegistry.address);

        thePioneersCollection = await CollectionContract.deploy(
            "TEST",
            "TT",
            baseURL,
            contractCID,
            partnershipProcessor.address
        );
        await thePioneersCollection.setIncomeVault(incomeVault.address);
        await vrfCoordinatorV2.addConsumer(subscriptionId, thePioneersCollection.address);

        const ownerFee = 2500;
        const discount = 2500;
        const constantDiscount = true;
        const levelFees: any = [];
        await referralRegistry.registerOwners([referrerAddress.address]);
        await partnershipProcessor.setProject(thePioneersCollection.address, 0, ownerFee, levelFees, discount, constantDiscount);
        await partnershipProcessor.registerPartnerPools(
            [referrerAddress.address],
            [{
                "gameDevPool": referrerAddress.address,
                "partnerPool": referrerAddress.address
            }]
        );    
    });
    async function mintToken(name: string, to: string, proof: string[], mintAmount: number, referrer = ethers.constants.AddressZero) {
        const mintTx = await thePioneersCollection.mint(name, to, proof, mintAmount, mintFee, { value: mintFee });
        const receipt = await mintTx.wait();

        let eventFilter = thePioneersCollection.filters.Transfer()
        let events = await thePioneersCollection.queryFilter(eventFilter)
        const tokenId = events[events.length - 1]?.args?.tokenId;
        return tokenId;
    }


    async function addSubcollection(name: string) {
        await thePioneersCollection.addSubcollection({
            name: name,
            baseCID: baseCID,
            merkleRoot: merkleMintWhitelistRoot,
            mintFee: mintFee,
            mainSupply: mainSupply,
            goldSupply: goldSupply,
            availableMainSupply: availableMainSupply,
            maxMintPerAddress: maxMintPerAddress,
        });
        await thePioneersCollection.setWhitelistMintEnabled(name, true)
    }

    describe("Standard flow", () => {

        it("Should show the correct URI after the mint", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);
            const tokenId = await mintToken(subcollectionName, owner.address, proof, 1);
            expect(await thePioneersCollection.tokenURI(tokenId)).to.be.equal(baseURL + defaultTokenCID + "/" + tokenId + ".json");
        });

        it("Should not mint without proof, when whitelist is enabled", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);
            await expect(
                thePioneersCollection.mint(subcollectionName, owner.address, [], 1, 250, { value: mintFee })
            ).to.be.revertedWithCustomError(thePioneersCollection,"NotOnWhitelist")
        });

        it("Should mint with pseudo-random ID assignment", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);
            const tokenId = await mintToken(subcollectionName, owner.address, proof, 1);
            expect(await thePioneersCollection.ownerOf(tokenId)).to.be.equal(owner.address);
            expect(tokenId).to.be.lessThanOrEqual(mainSupply - 1);
        });

        it("Should disable whitelist for minting and mint token without proof", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);
            await thePioneersCollection.setWhitelistMintEnabled(subcollectionName, false);
            await thePioneersCollection.setOpenMintEnabled(subcollectionName, true);
            const tokenId = await mintToken(subcollectionName, owner.address, [], 1);
            expect(await thePioneersCollection.ownerOf(tokenId)).to.be.equal(owner.address);
        });

        it("Should sell all tokens", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);

            const tokenIDs = new Set();
            for (let i = 0; i < mainSupply; i++) {
                const tokenId = await mintToken(subcollectionName, owner.address, proof, 1);
                tokenIDs.add(tokenId);
            }
            expect(tokenIDs.size).to.be.equal(mainSupply);
            expect(await thePioneersCollection.balanceOf(owner.address)).to.be.equal(mainSupply);

        });

    });

    describe("Extra tests", () => {
        it("Should allow the owner to add a sub-collection", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);
            const subcollectionId = await thePioneersCollection.getSubcollectionIdxByName(
                subcollectionName
            );
            expect(subcollectionId).to.equal(0);
        });

        it("Should not allow the owner to add a duplicate sub-collection", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);
            const subcollectionId = await thePioneersCollection.getSubcollectionIdxByName(
                subcollectionName
            );
            expect(subcollectionId).to.equal(0);
            await expect(addSubcollection(subcollectionName)).to.be
                .revertedWithCustomError(thePioneersCollection,"DuplicateName")
        });

        it("Should mint a token and assign it to the sender", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);
            const tokenId = await mintToken(subcollectionName, owner.address, proof, 1);
            const ownerOfToken = await thePioneersCollection.ownerOf(tokenId);
            expect(ownerOfToken).to.equal(owner.address);
        });

        it("Should transfer a token from one address to another", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);
            const tokenId = await mintToken(subcollectionName, owner.address, proof, 1);
            await thePioneersCollection
                .connect(owner)
                .transferFrom(owner.address, user.address, tokenId);
            const ownerOfToken = await thePioneersCollection.ownerOf(tokenId);
            expect(ownerOfToken).to.equal(user.address);
        });

        it("Should revert on available main supply exceeded", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);
            await thePioneersCollection.setAvailableMainSupply(subcollectionName, 1);
            await mintToken(subcollectionName, owner.address, proof, 1);
            await expect(thePioneersCollection.mint(subcollectionName, owner.address, proof, 1, 250, { value: mintFee }))
                .to.be.revertedWithCustomError(thePioneersCollection, "AvailableMainSupplyExceeded");
        });

        it("Should revert on max supply pre address exceeded", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);
            await thePioneersCollection.setMaxMintPerAddress(subcollectionName, 1);
            await mintToken(subcollectionName, owner.address, proof, 1);
            await expect(thePioneersCollection.mint(subcollectionName, owner.address, proof, 1, 250, { value: mintFee }))
                .to.be.revertedWithCustomError(thePioneersCollection, "MaxSupplyPerAddressExceeded");
        });

        it("Should set the trusted forwarder", async () => {
            const forwarder = owner.address;
            await thePioneersCollection.setTrustedForwarder(forwarder);
            const trustedForwarder = await thePioneersCollection.getTrustedForwarder();
            expect(trustedForwarder).to.equal(forwarder);
        });

        it("Should set the mint fee", async () => {
            const subcollectionName = "Subcollection1";
            const newMintFee = ethers.utils.parseEther("0.1");
            await addSubcollection(subcollectionName);
            await thePioneersCollection.setMintFee(subcollectionName, newMintFee);
            const mintFee = (await thePioneersCollection.subcollections(0)).params.mintFee;
            expect(mintFee).to.equal(newMintFee);
        });

        it("Should set the maximum number of tokens that can be minted by a single address", async () => {
            const subcollectionName = "Subcollection1";
            const maxMintPerAddress = 5;
            await addSubcollection(subcollectionName);
            const subcollectionId = await thePioneersCollection.getSubcollectionIdxByName(
                subcollectionName
            );
            await thePioneersCollection.setMaxMintPerAddress(subcollectionName, maxMintPerAddress);
            const retrievedMaxMintPerAddress = (
                await thePioneersCollection.subcollections(subcollectionId)
            ).params.maxMintPerAddress;
            expect(retrievedMaxMintPerAddress).to.equal(maxMintPerAddress);
        });

        it("Should set the whitelist minting option", async () => {
            const subcollectionName = "Subcollection1";
            const whitelistMintEnabled = true;
            await addSubcollection(subcollectionName);
            const subcollectionId = await thePioneersCollection.getSubcollectionIdxByName(
                subcollectionName
            );
            await thePioneersCollection.setWhitelistMintEnabled(
                subcollectionName,
                whitelistMintEnabled
            );
            const retrievedWhitelistMintEnabled = (
                await thePioneersCollection.subcollections(subcollectionId)
            ).whitelistMintEnabled;
            expect(retrievedWhitelistMintEnabled).to.equal(whitelistMintEnabled);
        });

        it("Should enable/disable the burn functionality", async () => {
            const subcollectionName = "Subcollection1";
            const burnEnabled = true;
            await addSubcollection(subcollectionName);
            const subcollectionId = await thePioneersCollection.getSubcollectionIdxByName(
                subcollectionName
            );
            await thePioneersCollection.setBurnEnabled(subcollectionName, burnEnabled);
            const retrievedBurnEnabled = (await thePioneersCollection.subcollections(subcollectionId))
                .burnEnabled;
            expect(retrievedBurnEnabled).to.equal(burnEnabled);
        });

        it("Should set the royalty information", async () => {
            const receiver = owner.address;
            const royaltyFeesInBips = 1000;
            const saleFee = 100;
            const royaltyFee = (saleFee * royaltyFeesInBips) / 10000;
            await thePioneersCollection.setRoyaltyInfo(receiver, royaltyFeesInBips);
            const royaltyInfo = await thePioneersCollection.royaltyInfo(0, 100);
            //   console.log(royaltyInfo);
            const retrievedReceiver = royaltyInfo[0];
            const retrievedRoyaltyFee = royaltyInfo[1];
            expect(retrievedReceiver).to.equal(receiver);
            expect(retrievedRoyaltyFee).to.equal(royaltyFee);
        });

        it("Should return the correct sub-collection ID by token ID", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);
            const tokenId = await mintToken(subcollectionName, owner.address, proof, 1);
            const subcollectionId = await thePioneersCollection.getSubcollectionIdxByTokenId(tokenId);
            expect(subcollectionId).to.equal(0);
        });

        it("Should revert when sending to the blacklisted address", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);
            await thePioneersCollection.setBlacklist(user.address, true);
            await expect(
                thePioneersCollection.mint(subcollectionName, user.address, proof, 1, 250, { value: mintFee })
            ).to.be.revertedWith("Address is blacklisted");
        });

        it("Should revert when approving to the blacklisted address", async () => {
            const subcollectionName = "Subcollection1";
            await addSubcollection(subcollectionName);
            await thePioneersCollection.setBlacklist(user.address, true);
            const tokenId = await mintToken(subcollectionName, owner.address, proof, 1);
            await expect(thePioneersCollection.approve(user.address, tokenId)).to.be.revertedWith(
                "Address is blacklisted"
            );
            await expect(
                thePioneersCollection.setApprovalForAll(user.address, true)
            ).to.be.revertedWith("Address is blacklisted");
        });

        it("Should revert when no nested collections", async () => {
            const subcollectionName = "Subcollection1";
            await expect(
                thePioneersCollection.mint(subcollectionName, owner.address, proof, 1, 250, {
                    value: mintFee,
                })
            ).to.be.revertedWithCustomError(thePioneersCollection, "NoNestedCollections");
        });

        it("Should allow the owner to remove a sub-collection", async () => {
            const subcollectionName1 = "Subcollection1";
            await addSubcollection(subcollectionName1);
            const subcollectionName2 = "Subcollection2";
            await addSubcollection(subcollectionName2);
            const subcollectionName3 = "Subcollection3";
            await addSubcollection(subcollectionName3);

            const tokenIds = [];
            for (let i = 0; i < 5; i++) {
                const tokenId = await mintToken(subcollectionName2, owner.address, proof, 1);
                tokenIds.push(tokenId);
            }

            // Check if the sub-collection exists
            const subcollectionIdBeforeRemoval = await thePioneersCollection.getSubcollectionIdxByName(
                subcollectionName2
            );
            expect(subcollectionIdBeforeRemoval).to.equal(1); // Assuming there are already two sub-collections

            // Remove the sub-collection
            await thePioneersCollection.removeSubcollection(subcollectionName2);

            // Check if the sub-collection has been removed
            await expect(
                thePioneersCollection.getSubcollectionIdxByName(subcollectionName2)
            ).to.be.revertedWithCustomError(thePioneersCollection, "InvalidCollection");

            expect(
                (await thePioneersCollection.subcollections(subcollectionIdBeforeRemoval)).params.name
            ).to.be.equal(subcollectionName3);

            // // Ensure that tokens from the removed sub-collection are no longer owned by the owner
            // for (let i = 0; i < 5; i++) {
            //     await expect(thePioneersCollection.ownerOf(tokenIds[i])).to.be
            //         .rejectedWith("ERC721: invalid token ID");
            // }

            const subcollectionName4 = "Subcollection4";
            await addSubcollection(subcollectionName4);
            expect(
                (await thePioneersCollection.subcollections(2)).params.name
            ).to.be.equal(subcollectionName4);
        });

        it("Should revert when removing a non-existent sub-collection", async () => {
            const subcollectionName1 = "Subcollection1";
            await addSubcollection(subcollectionName1);
            const nonExistentSubcollectionName = "NonExistentSubcollection";

            await expect(
                thePioneersCollection.getSubcollectionIdxByName(nonExistentSubcollectionName)
            ).to.be.revertedWithCustomError(thePioneersCollection, "InvalidCollection");

        });

        it("Should return the correct token URI", async () => {
            const subcollectionName1 = "Subcollection1";
            await addSubcollection(subcollectionName1);
            const subcollectionName2 = "Subcollection2";
            await addSubcollection(subcollectionName2);

            // Mint a token
            const tokenId = await mintToken(subcollectionName1, owner.address, proof, 1);

            const subcollectionId = await thePioneersCollection.getSubcollectionIdxByTokenId(tokenId);
            const collection = await thePioneersCollection.subcollections(subcollectionId);

            // Calculate the expected URI
            const expectedBaseURI = baseURL + collection.params.baseCID + "/";
            const expectedTokenURI = expectedBaseURI + tokenId.toString() + ".json";

            // Get the actual token URI
            const actualTokenURI = await thePioneersCollection.tokenURI(tokenId);

            // Check if the actual token URI matches the expected one
            expect(actualTokenURI).to.equal(expectedTokenURI);


        });

        it("Should return the correct token URIs for 5 tokens (with offset)", async () => {
            const subcollectionName1 = "Subcollection1";
            await addSubcollection(subcollectionName1);
            const subcollectionName2 = "Subcollection2";
            await addSubcollection(subcollectionName2);

            const subcollectionId = await thePioneersCollection.getSubcollectionIdxByName(subcollectionName2);
            const collection = await thePioneersCollection.subcollections(subcollectionId);
            const expectedBaseURI = baseURL + collection.params.baseCID + "/";

            for (let i = 0; i < 5; i++) {
                const tokenId = await mintToken(subcollectionName2, owner.address, proof, 1);

                const expectedTokenId = tokenId.toNumber() -
                    (await thePioneersCollection.subcollections(0)).endIndex.toNumber() -
                    (await thePioneersCollection.subcollections(0)).params.goldSupply.toNumber() - 1;

                const expectedTokenURI = expectedBaseURI + expectedTokenId.toString() + ".json";

                // Get the actual token URI
                const actualTokenURI = await thePioneersCollection.tokenURI(tokenId);

                // Check if the actual token URI matches the expected one
                expect(actualTokenURI).to.equal(expectedTokenURI);
            }
        });
    });
});
