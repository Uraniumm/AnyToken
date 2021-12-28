<<<<<<< HEAD
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IDEXRouter.sol";
//import "./SafeMath.sol";
import "./IDividendDistributor.sol";

contract DividendDistributor is IDividendDistributor {
    //using SafeMath for uint256;

    address _token;

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    struct RewardTokens{
        uint32 Token1;
        uint32 Token2;
        uint32 Slice1;
        uint32 Slice2;
    }

    address WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
    IDEXRouter router;

    address[] shareholders;
    address[] public PayoutTokenList;
    string[] public PayoutTokenListNames;
    mapping (address => uint256) shareholderIndexes;
    mapping (address => uint256) shareholderClaims;
    mapping (address => RewardTokens) public _RewardTokens;
    mapping (address => bool) private _SplitTokenRewards;
    mapping (address => Share) public shares;

    uint32 public NumberofPayoutTokens;
    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public dividendsPerShare;
    uint256 public dividendsPerShareAccuracyFactor = 10 ** 36;

    uint256 public minPeriod = 1 hours;
    uint256 public minDistribution = 1 * (10 ** 18);

    uint256 currentIndex;

    bool initialized;
    modifier initialization() {
        require(!initialized);
        _;
        initialized = true;
    }

    modifier onlyToken() {
        require(msg.sender == _token); _;
    }

    constructor (address _router) {
        router = _router != address(0)
        ? IDEXRouter(_router)
        : IDEXRouter(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
        _token = msg.sender;
        
        //BUSD.approve(_router, type(uint256).max);
        _AddTokentoPayoutList(0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7, "BUSD");
        _AddTokentoPayoutList(0x8BaBbB98678facC7342735486C851ABD7A0d17Ca, "ETH");
    }

    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external override onlyToken {
        minPeriod = _minPeriod;
        minDistribution = _minDistribution;
    }

    function setShare(address shareholder, uint256 amount) external override onlyToken {
        if(shares[shareholder].amount > 0){
            distributeDividend(shareholder);
        }

        if(amount > 0 && shares[shareholder].amount == 0){
            addShareholder(shareholder);
        }else if(amount == 0 && shares[shareholder].amount > 0){
            removeShareholder(shareholder);
        }

        totalShares = (totalShares - shares[shareholder].amount) + amount;
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
    }

    function deposit() external payable override onlyToken {
        //uint256 balanceBefore = BUSD.balanceOf(address(this));
        //uint256 balanceBefore = address(this).balance - msg.value;

        /*address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = address(BUSD);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(
            0,
            path,
            address(this),
            block.timestamp
        );*/

        //uint256 amount = BUSD.balanceOf(address(this)).sub(balanceBefore);
        uint256 amount = msg.value;

        //totalDividends += totalDividends.add(amount);
        totalDividends += amount;
        dividendsPerShare += (dividendsPerShareAccuracyFactor * amount) / totalShares;
    }

    function process(uint256 gas) external override onlyToken {
        uint256 shareholderCount = shareholders.length;

        if(shareholderCount == 0) { return; }

        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();

        uint256 iterations = 0;

        while(gasUsed < gas && iterations < shareholderCount) {
            if(currentIndex >= shareholderCount){
                currentIndex = 0;
            }

            if(shouldDistribute(shareholders[currentIndex])){
                distributeDividend(shareholders[currentIndex]);
            }

            gasUsed += gasLeft - gasleft();
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }
    }

    function shouldDistribute(address shareholder) internal view returns (bool) {
        return shareholderClaims[shareholder] + minPeriod < block.timestamp
        && getUnpaidEarnings(shareholder) > minDistribution;
    }

    function distributeDividend(address shareholder) internal {
        if(shares[shareholder].amount == 0){ return; }

        uint256 amount = getUnpaidEarnings(shareholder);
        if(amount > 0) {
            if(_SplitTokenRewards[shareholder] == false) {
                address PayoutTokenContract = PayoutTokenList[_RewardTokens[shareholder].Token1];
                /*if(PayoutTokenContract == address(BUSD)) {
                    totalDistributed = totalDistributed.add(amount);
                    BUSD.transfer(shareholder, amount);
                    shareholderClaims[shareholder] = block.timestamp;
                    shares[shareholder].totalRealised = shares[shareholder].totalRealised.add(amount);
                    shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
                }*/
                //else {
                    require(_swapBNBforChosenTokenandPayout(amount,PayoutTokenContract,shareholder));
                //}
            }
            else {
                address PayoutTokenContract;
                uint32 pie;
                uint32 percslice;
                uint32[2] memory tokennumbers;
                uint32[2] memory slices;

                tokennumbers[0] =   _RewardTokens[shareholder].Token1;
                tokennumbers[1] =   _RewardTokens[shareholder].Token2;
                slices[0] =   _RewardTokens[shareholder].Slice1;
                slices[1] =   _RewardTokens[shareholder].Slice2;

                uint256 slicevalue = amount / 100; //1%
                for(uint32 i = 0; i < 2; i++) {
                    uint256 BNBslice;
                    if((slices[i] > 0)&&(pie <= 100)) {
                        percslice = slices[i];
                        if(pie+percslice>100)// check for sneaky percentages
                            percslice = 100-pie;
                        pie += percslice;
                        BNBslice = slicevalue * percslice;
                        if(BNBslice>amount)
                            BNBslice = amount; //safety check
                        PayoutTokenContract = PayoutTokenList[tokennumbers[i]];
                        require(_swapBNBforChosenTokenandPayout(BNBslice,PayoutTokenContract,shareholder)); //{ 
                            amount -= BNBslice;
                        //}
                    }
                }
            }
            totalDistributed += amount;
            shareholderClaims[shareholder] = block.timestamp;
            shares[shareholder].totalRealised += amount;
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
        }
    }

    function claimDividend() external {
        distributeDividend(msg.sender);
    }

    function _swapBNBforChosenTokenandPayout(uint256 amountBNB,address PayoutTokenContract, address shareholder) private returns (bool) {
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = PayoutTokenContract;

    try router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountBNB}(
            0,
            path,
            address(shareholder),
            block.timestamp
        )
        {return true;}
        catch {}
        return false;
    }

    function getUnpaidEarnings(address shareholder) public view returns (uint256) {
        if(shares[shareholder].amount == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return (shareholderTotalDividends - shareholderTotalExcluded);
    }

    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return (share * dividendsPerShare) / dividendsPerShareAccuracyFactor;
    }

    function _AddTokentoPayoutList(address TokenAddress, string memory Name) private {
        PayoutTokenList.push(TokenAddress);
        PayoutTokenListNames.push(Name);
        NumberofPayoutTokens++;
    }

    function AddTokentoPayoutList(address TokenAddress, string memory Name) external override onlyToken {
        _AddTokentoPayoutList(TokenAddress, Name);
    }

    function EditPayoutList(uint32 pos, address TokenAddress, string memory Name) external override onlyToken {
        require(pos < NumberofPayoutTokens);
        PayoutTokenList[pos] = TokenAddress;
        PayoutTokenListNames[pos] = Name;
    }

    function ShowMyRewardTOKENS() public view returns (uint32[2] memory tokennumbers){
        tokennumbers[0] =   _RewardTokens[msg.sender].Token1;
        tokennumbers[1] =   _RewardTokens[msg.sender].Token2;
    
        return (tokennumbers);
    }
    
    //returns the names of all payout tokens    
    function ShowAllRewardTokens() public view returns (string[] memory Rewards){ 
        return PayoutTokenListNames;
    }

    //returns the percentage payout settings of the caller
    function ShowMyRewardSLICES() public view returns (uint32[2] memory slices){
        slices[0] =   _RewardTokens[msg.sender].Slice1; //percentage
        slices[1] =   _RewardTokens[msg.sender].Slice2;
    
        return (slices);
    }    

    function ChooseSinglePayoutToken(uint32 PayoutTokenNumber) public {
        require(PayoutTokenNumber < NumberofPayoutTokens);
        _RewardTokens[msg.sender].Token1 = PayoutTokenNumber;
        _RewardTokens[msg.sender].Slice1 = 100;
        _SplitTokenRewards[msg.sender] = false;
    }

    //token numbers + percentage slice
    function ChooseMultiplePayoutTokens(uint32 Token1,uint32 Slice1,uint32 Token2,uint32 Slice2) public {
       
        uint32 Whole = Slice1+Slice2;
        require(Whole > 0);
       
        uint32 N = uint32(NumberofPayoutTokens);
        bool OutofBounds = ((Token1 >= N)||(Token2 >= N));
        require(OutofBounds == false);

        _RewardTokens[msg.sender].Token1 = Token1;
        _RewardTokens[msg.sender].Token2 = Token2;
        _RewardTokens[msg.sender].Slice1 = Slice1;
        _RewardTokens[msg.sender].Slice2 = Slice2;
        
        _SplitTokenRewards[msg.sender] = true;
    }

    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);

        _SplitTokenRewards[shareholder] = false;
        _RewardTokens[shareholder].Slice1 = 100;
        _RewardTokens[shareholder].Slice2 = 0;
        _RewardTokens[shareholder].Token1 = 0;
        _RewardTokens[shareholder].Token2 = 1;
    }

    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[shareholders.length-1];
        shareholderIndexes[shareholders[shareholders.length-1]] = shareholderIndexes[shareholder];
        shareholders.pop();
    }
=======
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IDEXRouter.sol";
import "./SafeMath.sol";
import "./IDividendDistributor.sol";

contract DividendDistributor is IDividendDistributor {
    using SafeMath for uint256;

    address _token;

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    struct RewardTokens{
        uint32 Token1;
        uint32 Token2;
        uint32 Slice1;
        uint32 Slice2;
    }

    address WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
    IDEXRouter router;

    address[] shareholders;
    address[] public PayoutTokenList;
    string[] public PayoutTokenListNames;
    mapping (address => uint256) shareholderIndexes;
    mapping (address => uint256) shareholderClaims;
    mapping (address => RewardTokens) public _RewardTokens;
    mapping (address => bool) private _SplitTokenRewards;
    mapping (address => Share) public shares;

    uint32 public NumberofPayoutTokens;
    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public dividendsPerShare;
    uint256 public dividendsPerShareAccuracyFactor = 10 ** 36;

    uint256 public minPeriod = 1 hours;
    uint256 public minDistribution = 1 * (10 ** 18);

    uint256 currentIndex;

    bool initialized;
    modifier initialization() {
        require(!initialized);
        _;
        initialized = true;
    }

    modifier onlyToken() {
        require(msg.sender == _token); _;
    }

    constructor (address _router) {
        router = _router != address(0)
        ? IDEXRouter(_router)
        : IDEXRouter(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
        _token = msg.sender;
        
        _AddTokentoPayoutList(0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7, "BUSD");
        _AddTokentoPayoutList(0x8BaBbB98678facC7342735486C851ABD7A0d17Ca, "ETH");
    }

    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external override onlyToken {
        minPeriod = _minPeriod;
        minDistribution = _minDistribution;
    }

    function setShare(address shareholder, uint256 amount) external override onlyToken {
        if(shares[shareholder].amount > 0){
            distributeDividend(shareholder);
        }

        if(amount > 0 && shares[shareholder].amount == 0){
            addShareholder(shareholder);
        }else if(amount == 0 && shares[shareholder].amount > 0){
            removeShareholder(shareholder);
        }

        totalShares = totalShares.sub(shares[shareholder].amount).add(amount);
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
    }

    function deposit() external payable override onlyToken {
        uint256 amount = msg.value;

        totalDividends += amount;
        dividendsPerShare = dividendsPerShare.add(dividendsPerShareAccuracyFactor.mul(amount).div(totalShares));
    }

    function process(uint256 gas) external override onlyToken {
        uint256 shareholderCount = shareholders.length;

        if(shareholderCount == 0) { return; }

        uint256 gasUsed;
        uint256 gasLeft = gasleft();
        uint256 _currentIndex = currentIndex;
        uint256 iterations;

        while(gasUsed < gas && iterations < shareholderCount) {
            if(_currentIndex >= shareholderCount){
                delete currentIndex;
                _currentIndex = 0;
            }

            if(shouldDistribute(shareholders[_currentIndex])){
                distributeDividend(shareholders[_currentIndex]);
            }

            gasUsed = gasUsed.add(gasLeft.sub(gasleft()));
            gasLeft = gasleft();
            _currentIndex++;
            iterations++;
        }
        currentIndex = _currentIndex;
    }

    function shouldDistribute(address shareholder) internal view returns (bool) {
        return shareholderClaims[shareholder] + minPeriod < block.timestamp
        && getUnpaidEarnings(shareholder) > minDistribution;
    }

    function distributeDividend(address shareholder) internal {
        if(shares[shareholder].amount == 0){ return; }

        uint256 amount = getUnpaidEarnings(shareholder);
        if(amount > 0) {
            if(_SplitTokenRewards[shareholder] == false) {
                address PayoutTokenContract = PayoutTokenList[_RewardTokens[shareholder].Token1];
                _swapBNBforChosenTokenandPayout(amount,PayoutTokenContract,shareholder);
            }
            else {
                address PayoutTokenContract;
                uint32 pie;
                uint32 percslice;
                uint32[2] memory tokennumbers;
                uint32[2] memory slices;

                tokennumbers[0] =   _RewardTokens[shareholder].Token1;
                tokennumbers[1] =   _RewardTokens[shareholder].Token2;
                slices[0] =   _RewardTokens[shareholder].Slice1;
                slices[1] =   _RewardTokens[shareholder].Slice2;

                uint256 slicevalue = amount / 100;
                for(uint32 i = 0; i < 2; i++) {
                    
                    uint256 BNBslice;
                    
                    if((slices[i] > 0) && (pie <= 100)) {
                        
                        percslice = slices[i];
                        
                        if(pie+percslice > 100)// check for sneaky percentages
                            percslice = 100-pie;
                        
                        pie += percslice;
                        BNBslice = slicevalue * percslice;
                        
                        if(BNBslice > amount)
                            BNBslice = amount; //safety check
                        
                        PayoutTokenContract = PayoutTokenList[tokennumbers[i]];
                        
                        if(_swapBNBforChosenTokenandPayout(BNBslice,PayoutTokenContract,shareholder)) { 
                            amount -= BNBslice;
                        }
                    }
                }
            }
            totalDistributed = totalDistributed.add(amount);
            shareholderClaims[shareholder] = block.timestamp;
            shares[shareholder].totalRealised = shares[shareholder].totalRealised.add(amount);
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
        }
    }

    function claimDividend() external {
        distributeDividend(msg.sender);
    }

    function _swapBNBforChosenTokenandPayout(uint256 amountBNB,address PayoutTokenContract, address shareholder) private returns (bool) {
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = PayoutTokenContract;

    try router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountBNB}(
            0,
            path,
            address(shareholder),
            block.timestamp
        )
        {return true;}
        catch {}
        return false;
    }

    function getUnpaidEarnings(address shareholder) public view returns (uint256) {
        if(shares[shareholder].amount == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }

    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return share.mul(dividendsPerShare).div(dividendsPerShareAccuracyFactor);
    }

    function _AddTokentoPayoutList(address TokenAddress, string memory Name) private {
        PayoutTokenList.push(TokenAddress);
        PayoutTokenListNames.push(Name);
        NumberofPayoutTokens++;
    }

    function AddTokentoPayoutList(address TokenAddress, string memory Name) external override onlyToken {
        _AddTokentoPayoutList(TokenAddress, Name);
    }

    function EditPayoutList(uint32 pos, address TokenAddress, string memory Name) external override onlyToken {
        require(pos < NumberofPayoutTokens);
        PayoutTokenList[pos] = TokenAddress;
        PayoutTokenListNames[pos] = Name;
    }

    function ShowMyRewardTOKENS() public view returns (uint32[2] memory tokennumbers){
        tokennumbers[0] =   _RewardTokens[msg.sender].Token1;
        tokennumbers[1] =   _RewardTokens[msg.sender].Token2;
    
        return (tokennumbers);
    }
    
    //returns the names of all payout tokens    
    function ShowAllRewardTokens() public view returns (string[] memory Rewards){ 
        return PayoutTokenListNames;
    }

    //returns the percentage payout settings of the caller
    function ShowMyRewardSLICES() public view returns (uint32[2] memory slices){
        slices[0] =   _RewardTokens[msg.sender].Slice1; //percentage
        slices[1] =   _RewardTokens[msg.sender].Slice2;
    
        return (slices);
    }    

    function ChooseSinglePayoutToken(uint32 PayoutTokenNumber) public {
        require(PayoutTokenNumber < NumberofPayoutTokens);
        _RewardTokens[msg.sender].Token1 = PayoutTokenNumber;
        _RewardTokens[msg.sender].Slice1 = 100;
        _SplitTokenRewards[msg.sender] = false;
    }

    //token numbers + percentage slice
    function ChooseMultiplePayoutTokens(uint32 Token1,uint32 Slice1,uint32 Token2,uint32 Slice2) public {
       
        uint32 Whole = Slice1+Slice2;
        require(Whole > 0);
       
        uint32 N = uint32(NumberofPayoutTokens);
        bool OutofBounds = ((Token1 >= N)||(Token2 >= N));
        require(OutofBounds == false);

        _RewardTokens[msg.sender].Token1 = Token1;
        _RewardTokens[msg.sender].Token2 = Token2;
        _RewardTokens[msg.sender].Slice1 = Slice1;
        _RewardTokens[msg.sender].Slice2 = Slice2;
        
        _SplitTokenRewards[msg.sender] = true;
    }

    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);

        _SplitTokenRewards[shareholder] = false;
        _RewardTokens[shareholder].Slice1 = 100;
        _RewardTokens[shareholder].Slice2 = 0;
        _RewardTokens[shareholder].Token1 = 0;
        _RewardTokens[shareholder].Token2 = 1;
    }

    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[shareholders.length-1];
        shareholderIndexes[shareholders[shareholders.length-1]] = shareholderIndexes[shareholder];
        shareholders.pop();
    }
>>>>>>> main
}