//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;
interface IDividendDistributor {
    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external;
    function _setRouterAddress(address _router) external;
    function setShare(address shareholder, uint256 amount) external;
    function _setRouterAddress(address _router) external;
    function deposit() external payable;
    function process(uint256 gas) external;
    function AddTokentoPayoutList(address TokenAddress, string memory Name) external;
    function EditPayoutList(uint32 pos, address TokenAddress, string memory Name) external;
}