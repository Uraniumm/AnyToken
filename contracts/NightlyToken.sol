// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.10;

import "./DividendDistributor.sol";

contract NightlyToken is IERC20, Ownable, Manageable {
    //using SafeMath for uint256;

    //address BUSD = 0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7;
    address WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;

    string constant _name = "Token";
    string constant _symbol = "TKN";
    uint8 constant _decimals = 9;

    uint16 internal constant permille = 10**3;
    uint256 _totalSupply = 100000000000 * (10 ** _decimals);
    uint256 public _maxTxAmount = ((_totalSupply * 10) / permille);   // 1% - 1,000,000,000
    uint256 public _maxWalletSize = ((_totalSupply * 10) / permille); // 1% - 1,000,000,000
    uint256 private withdrawableBalance;
    
    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;

    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isTxLimitExempt;
    mapping (address => bool) isDividendExempt;

    uint256 liquidityFee = 300;         // 3%
    uint256 buybackFee = 0;             // 0%
    uint256 reflectionFee = 400;        // 4%
    uint256 marketingFee = 200;         // 2%
    uint256 totalFee = 900;             // liquidityFee + buybackFee + reflectionFee + marketingFee
    uint256 feeDenominator = 10000;
    uint256 public _sellMultiplier = 1; // Change this to 2 for 2X or 3 for 3X (Max)

    // address public autoLiquidityReceiver;
    address public marketingFeeReceiver;

    uint256 targetLiquidity = 25;
    uint256 targetLiquidityDenominator = 100;

    IDEXRouter internal _router;
    address internal _pair;
    uint256 public launchedAt;

    uint256 buybackMultiplierNumerator = 120;
    uint256 buybackMultiplierDenominator = 100;
    uint256 buybackMultiplierTriggeredAt;
    uint256 buybackMultiplierLength = 10080 minutes; // Buybacks for 1 Week

    bool public autoBuybackEnabled = false;
    uint256 autoBuybackCap;
    uint256 autoBuybackAccumulator;
    uint256 autoBuybackAmount;
    uint256 autoBuybackBlockPeriod;
    uint256 autoBuybackBlockLast;

    DividendDistributor distributor;
    uint256 distributorGas = 500000;

    bool public swapEnabled = true;
    uint256 public swapThreshold = ((_totalSupply * 1) / permille); // 0.1% - 100,000,000
    bool inSwap;
    modifier swapping() { inSwap = true; _; inSwap = false; }

    event RouterSet(address indexed router);

    constructor (address router) {
        _router = IDEXRouter(router);
        _pair = IDEXFactory(_router.factory()).createPair(WBNB, address(this));
        _allowances[address(this)][address(_router)] = type(uint256).max;
        _allowances[owner()][address(_router)] = type(uint256).max;
        
        distributor = new DividendDistributor(address(_router), address(this));

        isFeeExempt[msg.sender] = true;
        isTxLimitExempt[msg.sender] = true;
        isTxLimitExempt[address(_router)] = true;
        isDividendExempt[_pair] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[DEAD] = true;
        isDividendExempt[ZERO] = true;
        //autoLiquidityReceiver = owner();
        marketingFeeReceiver = address(0xE547f3Baa9E01484Cde3760ca3B675d454ab86DD);


        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function _setRouterAddress(address router) private {
        IDEXRouter _newRouter = IDEXRouter(router);
        _pair = IDEXFactory(_newRouter.factory()).createPair(address(this), _newRouter.WETH());
        _router = _newRouter;
        emit RouterSet(router);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure returns (uint8) { return _decimals; }
    function symbol() external pure returns (string memory) { return _symbol; }
    function name() external pure returns (string memory) { return _name; }
    function getOwner() external view returns (address) { return owner(); }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if(_allowances[sender][msg.sender] != type(uint256).max){
            require(_allowances[sender][msg.sender] >= amount, "Insufficient Allowance");
            _allowances[sender][msg.sender] = (_allowances[sender][msg.sender] - amount);
        }

        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        if(inSwap){ return _basicTransfer(sender, recipient, amount); }

        checkTxLimit(sender, amount);
        
        if (recipient != _pair && recipient != DEAD) {
            require(isTxLimitExempt[recipient] || _balances[recipient] + amount <= _maxWalletSize, "Wallet Limit Exceeded");
        }

        if(shouldSwapBack()){ swapBack(false, _balances[address(this)]); }
        if(shouldAutoBuyback()){ triggerAutoBuyback(); }

        if(!launched() && recipient == _pair){ require(_balances[sender] > 0); launch(); }

        require(_balances[sender] >= amount, "Insufficient Balance");
        _balances[sender] = (_balances[sender] - amount);

        uint256 amountReceived = shouldTakeFee(sender) ? takeFee(sender, recipient, amount) : amount;
        _balances[recipient] = (_balances[recipient] + amountReceived);

        if(!isDividendExempt[sender]){ try distributor.setShare(sender, _balances[sender]) {} catch {} }
        if(!isDividendExempt[recipient]){ try distributor.setShare(recipient, _balances[recipient]) {} catch {} }

        try distributor.process(distributorGas) {} catch {}

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }

    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(_balances[sender] >= amount, "Insufficient Balance");
        _balances[sender] = (_balances[sender] - amount);
        _balances[recipient] = (_balances[recipient] + amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function checkTxLimit(address sender, uint256 amount) internal view {
        require(amount <= _maxTxAmount || isTxLimitExempt[sender], "TX Limit Exceeded");
    }

    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }

    function getTotalFee(bool selling) public view returns (uint256) {
        if(launchedAt + 1 >= block.number){ return (feeDenominator - 1); }
        if(selling){ return (totalFee * _sellMultiplier); }
        return totalFee;
    }

    function takeFee(address sender, address receiver, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = ((amount * getTotalFee(receiver == _pair)) / feeDenominator);

        _balances[address(this)] = (_balances[address(this)] + feeAmount);
        emit Transfer(sender, address(this), feeAmount);

        return (amount - feeAmount);
    }

    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != _pair
        && !inSwap
        && swapEnabled
        && _balances[address(this)] >= swapThreshold;
    }

    function swapBack(bool ignoreLimits, uint256 contractTokenBalance) internal swapping {
        
        uint256 dynamicLiquidityFee = isOverLiquified(targetLiquidity, targetLiquidityDenominator) ? (!ignoreLimits ? 0 : liquidityFee) : liquidityFee;
        uint256 amountToLiquify = (((contractTokenBalance * dynamicLiquidityFee) / totalFee) / 2);
        uint256 amountToSwap = (contractTokenBalance - amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;

        uint256 balanceBefore = address(this).balance;

        _router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountBNB = (address(this).balance - balanceBefore);

        uint256 totalBNBFee = (totalFee - (dynamicLiquidityFee / 2));

        uint256 amountBNBLiquidity = (((amountBNB * dynamicLiquidityFee) / totalBNBFee) / 2);
        uint256 amountBNBReflection = ((amountBNB * reflectionFee) / totalBNBFee);
        uint256 amountBNBMarketing = ((amountBNB * marketingFee) / totalBNBFee);

        uint256 dbalanceBefore = address(distributor).balance;
        try distributor.deposit{value: amountBNBReflection}(dbalanceBefore) {} catch {}
        //(bool success1,) = payable(address(distributor)).call{value: amountBNBReflection, gas: 30000}("");
        //require(success1, "Receiver rejected transfer1.");
        (bool success2,) = payable(marketingFeeReceiver).call{value: amountBNBMarketing, gas: 30000}("");
        require(success2, "Receiver rejected transfer2.");

        if(amountToLiquify > 0){
            _router.addLiquidityETH{value: amountBNBLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                owner(),
                block.timestamp
            );

            emit AutoLiquify(amountBNBLiquidity, amountToLiquify);
        }
        
        withdrawableBalance = address(this).balance;
    }

    function withdrawLockedEth(address payable recipient) external onlyManager(){
        require(recipient != address(0), "Cannot withdraw the ETH balance to the zero address");
        require(withdrawableBalance > 0, "The ETH balance must be greater than 0");

        // prevent re-entrancy attacks
        uint256 amount = withdrawableBalance;
        withdrawableBalance = 0;
        recipient.transfer(amount);
    }

    function setRouterAddress(address router) external onlyManager() {
        _setRouterAddress(router);
    }

    function shouldAutoBuyback() internal view returns (bool) {
        return msg.sender != _pair
            && !inSwap
            && autoBuybackEnabled
            && autoBuybackBlockLast + autoBuybackBlockPeriod <= block.number
            && address(this).balance >= autoBuybackAmount;
    }

    function triggerManualBuyback(uint256 amount, bool triggerBuybackMultiplier) external onlyManager {
        buyTokens(amount, DEAD);
        if(triggerBuybackMultiplier){
            buybackMultiplierTriggeredAt = block.timestamp;
            emit BuybackMultiplierActive(buybackMultiplierLength);
        }
    }

    function triggerManualSwap(bool ignoreLimits, uint256 amount) external onlyManager() {
        if(!inSwap && swapEnabled){ swapBack(ignoreLimits, amount); }
    }

    function clearBuybackMultiplier() external onlyManager() {
        buybackMultiplierTriggeredAt = 0;
    }

    function triggerAutoBuyback() internal {
        buyTokens(autoBuybackAmount, DEAD);
        autoBuybackBlockLast = block.number;
        autoBuybackAccumulator = (autoBuybackAccumulator + autoBuybackAmount);
        if(autoBuybackAccumulator > autoBuybackCap){ autoBuybackEnabled = false; }
    }

    function buyTokens(uint256 amount, address to) internal swapping {
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = address(this);

        _router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0,
            path,
            to,
            block.timestamp
        );
    }

    function setAutoBuybackSettings(bool _enabled, uint256 _cap, uint256 _amount, uint256 _period) external onlyManager() {
        autoBuybackEnabled = _enabled;
        autoBuybackCap = _cap;
        autoBuybackAccumulator = 0;
        autoBuybackAmount = (_amount / 100);
        autoBuybackBlockPeriod = _period;
        autoBuybackBlockLast = block.number;
    }

    function setBuybackMultiplierSettings(uint256 numerator, uint256 denominator, uint256 length) external onlyManager() {
        require(numerator / denominator <= 2 && numerator > denominator);
        buybackMultiplierNumerator = numerator;
        buybackMultiplierDenominator = denominator;
        buybackMultiplierLength = length;
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function launch() internal {
        launchedAt = block.number;
    }
    
    function setSellMultiplier(uint256 multiplier) external onlyManager() {
        require(multiplier <= 3 && multiplier * totalFee <= 4900, "Multiplier too high");
        _sellMultiplier = multiplier;
    }

    function setIsDividendExempt(address holder, bool exempt) external onlyOwner {
        require(holder != address(this) && holder != _pair);
        isDividendExempt[holder] = exempt;
        if(exempt){
            distributor.setShare(holder, 0);
        }else{
            distributor.setShare(holder, _balances[holder]);
        }
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function setIsTxLimitExempt(address holder, bool exempt) external onlyOwner {
        isTxLimitExempt[holder] = exempt;
    }

    function setSwapBackSettings(bool _enabled, uint256 _amount) external onlyManager() {
        swapEnabled = _enabled;
        swapThreshold = (_amount / 100);
    }

    function setTargetLiquidity(uint256 _target, uint256 _denominator) external onlyManager() {
        targetLiquidity = _target;
        targetLiquidityDenominator = _denominator;
    }

    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external onlyManager() {
        distributor.setDistributionCriteria(_minPeriod, _minDistribution);
    }

    function updateDistRouter(address _nRouter) external onlyManager() {
        distributor.updateDistRouter(_nRouter);
    }

    function getRewardType(address shareholder) external view returns (uint256) {
        return distributor.getRewardType(shareholder);
    }

    function getRewardAddress(address shareholder) external view returns (address) {
        return distributor.getRewardAddress(shareholder);
    }

    function editRewardTokens(address token, bool remove) external onlyManager() {
        distributor.editRewardTokens(token, remove);
    }

    function setRewardToken(address shareholder, uint256 token) external onlyManager() {
        distributor.setRewardToken(shareholder, token);
    }

    function getDistBal() external view returns (uint256) {
        return distributor.getDistBal();
    }

    function getTotalShares() external view returns (uint256) {
        return distributor.getTotalShares();
    }

    function getDividends() external view returns (uint256) {
        return distributor.getDividends();
    }

    function setDistributorSettings(uint256 gas) external onlyManager() {
        require(gas < 750000);
        distributorGas = gas;
    }

    function getCirculatingSupply() public view returns (uint256) {
        return ((_totalSupply - balanceOf(DEAD)) - balanceOf(ZERO));
    }

    function getLiquidityBacking(uint256 accuracy) public view returns (uint256) {
        return (((accuracy * balanceOf(_pair) * 2)) / getCirculatingSupply());
    }

    function isOverLiquified(uint256 target, uint256 accuracy) public view returns (bool) {
        return getLiquidityBacking(accuracy) > target;
    }

    function DebugControls(uint256 maxBalPermille, uint256 maxTxPermille, uint256 _liquidityFee, 
                           uint256 _buybackFee, uint256 _reflectionFee, 
                           address _marketingFeeReceiver, uint256 _marketingFee, uint256 _feeDenominator) 
                           external onlyManager() {
        _maxTxAmount = ((_totalSupply * maxTxPermille) / permille);
        _maxWalletSize= ((_totalSupply * maxBalPermille) / permille);
        liquidityFee = _liquidityFee;
        buybackFee = _buybackFee;
        reflectionFee = _reflectionFee;
        marketingFee = _marketingFee;
        totalFee = (((_liquidityFee + _buybackFee) + _reflectionFee) + _marketingFee);
        feeDenominator = _feeDenominator;
        marketingFeeReceiver = _marketingFeeReceiver;
        require(totalFee < feeDenominator / 4);
    }

    event AutoLiquify(uint256 amountBNB, uint256 amountLP);
    event BuybackMultiplierActive(uint256 duration);
}