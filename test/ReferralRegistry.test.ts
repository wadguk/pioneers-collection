import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { expect } from "chai";

describe("ReferralRegistry", () => {
    let owner: Signer;
    let trustedSigner: Signer;
    let trustedDapp: Signer;
    let referrer: Signer;
    let alice: Signer;
    let bob: Signer;
    let referralRegistry: Contract;

    beforeEach(async () => {
        [owner, trustedSigner, trustedDapp, referrer, alice, bob] = await ethers.getSigners();

        const ReferralRegistryFactory = await ethers.getContractFactory("ReferralRegistry");
        referralRegistry = await ReferralRegistryFactory.deploy();
        await referralRegistry.deployed();
    });

    it("should add referral", async () => {
        await referralRegistry.grantRole(await referralRegistry.TRUSTED_DAPP_ROLE(), await trustedDapp.getAddress());

        const referrerAddress = await referrer.getAddress();
        const aliceAddress = await alice.getAddress();

        await referralRegistry.registerOwners([referrerAddress]);

        await referralRegistry.connect(trustedDapp).addReferral(referrerAddress, aliceAddress);

        const _referrer = await referralRegistry.getReferrer(aliceAddress);
        const _owner = await referralRegistry.getCommunityOwner(aliceAddress);
        const _level = await referralRegistry.getReferralLevel(aliceAddress);

        expect(_referrer).to.equal(referrerAddress);
        expect(_owner).to.equal(referrerAddress);
        expect(_level).to.equal(1);
    });

    it("should get referral tree", async () => {
        await referralRegistry.grantRole(await referralRegistry.TRUSTED_DAPP_ROLE(), await trustedDapp.getAddress());

        const referrerAddress = await referrer.getAddress();
        const aliceAddress = await alice.getAddress();
        const bobAddress = await bob.getAddress();

        await referralRegistry.setRequireOwner(false);

        await referralRegistry.registerOwners([referrerAddress]);

        await referralRegistry.connect(trustedDapp).addReferral(referrerAddress, aliceAddress);
        await referralRegistry.connect(trustedDapp).addReferral(aliceAddress, bobAddress);

        const tree = await referralRegistry.getReferralTree(referrerAddress);

        expect(tree.length).to.equal(3);
        expect(tree[0].addr).to.equal(referrerAddress);
        expect(tree[0].level).to.equal(0);
        expect(tree[1].addr).to.equal(aliceAddress);
        expect(tree[1].level).to.equal(1);
    });
});
