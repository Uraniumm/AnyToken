const Token = artifacts.require("Token");
const DividendDistributor = artifacts.require("DividendDistributor");

module.exports = function(deployer) {
  deployer.deploy(Token);
  deployer.link(Token, DividendDistributor);
  deployer.deploy(DividendDistributor);
};
