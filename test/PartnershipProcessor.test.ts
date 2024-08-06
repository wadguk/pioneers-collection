import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";
import { expect } from "chai";

describe("PartnershipProcessor", () => {
    let owner: Signer;
    let trustedSigner: Signer;
    let trustedDapp: Signer;
    let referrer: Signer;
    let referee: Signer;
    let partnershipProcessor: Contract;
    let referralRegistry: Contract;

    let ownerAddress: string;
    let trustedSignerAddress: string;
    let trustedDappAddress: string;
    let referrerAddress: string;
    let refereeAddress: string;

    beforeEach(async () => {
        [owner, trustedSigner, trustedDapp, referrer, referee] = await ethers.getSigners();

        ownerAddress = await owner.getAddress();
        trustedSignerAddress = await trustedSigner.getAddress();
        trustedDappAddress = await trustedDapp.getAddress();
        referrerAddress = await referrer.getAddress();
        refereeAddress = await referee.getAddress();

        const ReferralRegistryFactory = await ethers.getContractFactory("ReferralRegistry");
        referralRegistry = await ReferralRegistryFactory.deploy();
        await referralRegistry.deployed();
        await referralRegistry.registerOwners([referrerAddress]);

        const partnershipProcessorFactory = await ethers.getContractFactory("PartnershipProcessor");
        partnershipProcessor = await partnershipProcessorFactory.deploy(referralRegistry.address);
        await partnershipProcessor.deployed();

        const ownerFee = 2500;
        const discount = 2500;
        const constantDiscount = true;
        const levelFees: any = [];
        await partnershipProcessor.setProject(trustedDappAddress, 0, ownerFee, levelFees, discount, constantDiscount);
        await partnershipProcessor.registerPartnerPools(
            [referrerAddress],
            [{
                "gameDevPool": referrerAddress,
                "partnerPool": referrerAddress
            }]
        );

    });

    it("should process referral operation with discount", async () => {

        await partnershipProcessor.grantRole(await partnershipProcessor.TRUSTED_SIGNER_ROLE(), trustedDappAddress);
        await partnershipProcessor.grantRole(await partnershipProcessor.TRUSTED_DAPP_ROLE(), trustedDappAddress);
        await referralRegistry.grantRole(await partnershipProcessor.TRUSTED_DAPP_ROLE(), trustedDappAddress);

        await referralRegistry.registerOwners([ownerAddress])
        await referralRegistry.connect(trustedDapp).addReferral(referrerAddress, refereeAddress);

        const initialBalance = await ethers.provider.getBalance(referrerAddress);
        const initialFee = ethers.utils.parseEther("1.0");
        const subIndex = 0;

        const tx = await partnershipProcessor.connect(trustedDapp).processPartnershipOperation(
            refereeAddress,
            initialFee,
            subIndex,
            { value: initialFee }
        );

        await expect(tx)
            .to.emit(partnershipProcessor, "OperationProcessed")
            .withArgs(trustedDappAddress, referrerAddress, refereeAddress, initialFee);

        const finalBalance = await ethers.provider.getBalance(referrerAddress);
        expect(finalBalance).to.gt(initialBalance);

    });
});
