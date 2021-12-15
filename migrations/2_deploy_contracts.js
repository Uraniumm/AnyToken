const DividendDistributor = artifacts.require("DividendDistributor");
const NightlyToken = artifacts.require("NightlyToken");
const router = "0x10ED43C718714eb63d5aA57B78B54704E256024E";
 
module.exports = function (deployer) {
  deployer.deploy(NightlyToken, router).then(async () => {
    // get instance of deployed Favourite contract
    const nToken = await NightlyToken.deployed();
    // deploy and pass arguments
    await deployer.deploy(DividendDistributor, router, nToken.address);
    // get instance of deployed Vote contract
    // const vInstance = await Vote.deployed();
    // set Vote address in Favourite
    // await fInstance.setVoteAddress(vInstance.address);
  });
};