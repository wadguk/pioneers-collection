import * as dotenv from "dotenv";
dotenv.config();

const TRUSTED_SIGNER = process.env.TRUSTED_SIGNER;
const VRF_COORDINATOR = process.env.VRF_COORDINATOR;
const KEY_HASH = process.env.KEY_HASH;
const SUBSCRIPTION_ID = process.env.SUBSCRIPTION_ID;

export const deployPioneersCollection = async (referralProcessor: string | undefined, hre: any) => {
    await hre.run("printDeployInfo");
    
    const name = "TEST";
    const symbol = "TEST";
    const contractCID = "TESTAWfaSoDFGa15JDG2928fAWfN";
    const baseURL = "https://test.com/ipfs/"

    const VRFCoordinatorV2MockFactory = await hre.ethers.getContractFactory("VRFCoordinatorV2Mock");
    const vrfCoordinatorV2MockFactory = await VRFCoordinatorV2MockFactory.attach(VRF_COORDINATOR);

    const CollectionTokenFactory = await hre.ethers.getContractFactory("PioneersCollection");
    const collectionToken = await CollectionTokenFactory.deploy(
        name,
        symbol,
        baseURL,
        contractCID,
        VRF_COORDINATOR,
        SUBSCRIPTION_ID,
        KEY_HASH,
        referralProcessor,
        { gasLimit: 8000000 }
    );
    await collectionToken.deployTransaction.wait(6);
    console.log("Collection token deployed to:", collectionToken.address);

    const tx = await vrfCoordinatorV2MockFactory.addConsumer(
        SUBSCRIPTION_ID,
        collectionToken.address
    );
    await tx.wait()
    console.log("Add VRF consumer:", tx.hash);

    const DEFAULT_ADMIN_ROLE = await collectionToken.DEFAULT_ADMIN_ROLE();
    const TRUSTED_SIGNER_ROLE = await collectionToken.TRUSTED_SIGNER_ROLE();

    await (await collectionToken.grantRole(TRUSTED_SIGNER_ROLE, TRUSTED_SIGNER)).wait();
    await (await collectionToken.grantRole(DEFAULT_ADMIN_ROLE, TRUSTED_SIGNER)).wait();

    try {
        await hre.run("verify:verify", {
            address: collectionToken.address,
            constructorArguments: [
                name,
                symbol,
                baseURL,
                contractCID,
                VRF_COORDINATOR,
                SUBSCRIPTION_ID,
                KEY_HASH,
                referralProcessor
            ],
            contract: "contracts/PioneersCollection.sol:PioneersCollection",
        });
    } catch (e: any) {
        console.log(e.message);
    }
};