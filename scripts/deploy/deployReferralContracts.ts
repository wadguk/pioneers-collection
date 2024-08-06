export const deployReferralContracts = async (hre: any) => {
    await hre.run("printDeployInfo");
    
    const ReferralRegistry = await hre.ethers.getContractFactory('ReferralRegistry');
    const referralRegistry = await ReferralRegistry.deploy();
    await referralRegistry.deployTransaction.wait(6);
    console.log("ReferralRegistry", referralRegistry.address);

    try {
        await hre.run("verify:verify", {
            address: referralRegistry.address,
            constructorArguments: [],
            contract: "contracts/test/ReferralRegistry.sol:ReferralRegistry",
        });
    } catch (e: any) {
        console.log(e.message);
    }


    const ReferralProcessor = await hre.ethers.getContractFactory('ReferralProcessor');
    const referralProcessor = await ReferralProcessor.deploy(referralRegistry.address, { gasLimit: 5000000 });
    await referralProcessor.deployTransaction.wait(6);
    console.log("ReferralProcessor", referralProcessor.address);

    try {
        await hre.run("verify:verify", {
            address: referralProcessor.address,
            constructorArguments: [referralRegistry.address],
            contract: "contracts/ReferralProcessor.sol:ReferralProcessor",
        });
    } catch (e: any) {
        console.log(e.message);
    }

}