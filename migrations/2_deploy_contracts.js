const DividendDistributor = artifacts.require("DividendDistributor");
const NightlyToken = artifacts.require("NightlyToken");
const router = "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3";
 
module.exports = function (deployer) {
  deployer.deploy(NightlyToken, router).then(async () => {
    // get instance of deployed Favourite contract
    const nToken = await NightlyToken.deployed();
    // deploy and pass arguments
    await deployer.deploy(DividendDistributor, nToken.address, router);
    // get instance of deployed Vote contract
    // const vInstance = await Vote.deployed();
    // set Vote address in Favourite
    // await fInstance.setVoteAddress(vInstance.address);
  });
};