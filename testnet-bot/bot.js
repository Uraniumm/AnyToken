import ethers, { BigNumber } from 'ethers';
import express from 'express';
import chalk from 'chalk';
import dotenv from 'dotenv';
import inquirer from 'inquirer';

const app = express();
dotenv.config();

const data = {
  WBNB: process.env.WBNB_CONTRACT, //wbnb

  to_PURCHASE: process.env.TO_PURCHASE, // token that you will purchase = BUSD for test '0xe9e7cea3dedca5984780bafc599bd69add087d56'

  MIN_WBNB : process.env.MIN_WBNB,

  factory: process.env.FACTORY,  //PancakeSwap V2 factory

  router: process.env.ROUTER, //PancakeSwap V2 router

  recipient: process.env.YOUR_ADDRESS, //your wallet address,

  Slippage : process.env.SLIPPAGE, //in Percentage

  gasPrice : ethers.utils.parseUnits(`${process.env.GWEI}`, 'gwei'), //in gwei
  
  gasLimit : process.env.GAS_LIMIT, //at least 21000

  gasLimitSell : process.env.GAS_LIMIT_SELL, //at least 800000

  minBnb : process.env.MIN_LIQUIDITY_ADDED, //min liquidity added

  contractABI : process.env.CONTRACT_ABI //needed to check balsTIMEOUT
}

let initialLiquidityDetected = false;
let jmlBnb = 0;

const bscMainnetUrl = 'https://data-seed-prebsc-1-s1.binance.org:8545/'
const mnemonic = process.env.YOUR_MNEMONIC //your memonic;
const tokenIn = data.WBNB;
const tokenOut = data.to_PURCHASE;
const provider = new ethers.providers.JsonRpcProvider(bscMainnetUrl)
const wallet = new ethers.Wallet(mnemonic);
const account = wallet.connect(provider);
let buildNumber = "halo3 cache debug xenon 06099.06.12.16.1108.alpha  Dec  16 2006 11:08:51";

const factory = new ethers.Contract(
  data.factory,
  [
    'event PairCreated(address indexed token0, address indexed token1, address pair, uint)',
    'function getPair(address tokenA, address tokenB) external view returns (address pair)'
  ],
  account
);

const router = new ethers.Contract(
  data.router,
  [
    'function getAmountsOut(uint amountIn, address[] memory path) public view returns (uint[] memory amounts)',
    'function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts)',
    'function swapETHForExactTokens(uint256 amountOutMin, address[] path, address to, uint256 deadline) external payable returns (uint[] memory amounts)',
    `function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256 amountIn, uint256 amountOutMin, address[] path, address to, uint256 deadline)`,
    'function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts)',
    'function swapExactTokensForTokensSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts)'
  ],
  account
);

const erc = new ethers.Contract(
  data.WBNB,
  [{"constant": true,"inputs": [{"name": "_owner","type": "address"}],"name": "balanceOf","outputs": [{"name": "balance","type": "uint256"}],"payable": false,"type": "function"}],
  account
);

const tst = new ethers.Contract(
  data.to_PURCHASE,
  data.contractABI,
  account
);  

const run = async () => {
    try {
        console.log('\x1b[42m')
        console.clear();
        console.log(`${buildNumber}`);
        await setupTx();
        await setApproval();
        await doTx();
        setTimeout(() => { run(); }, 2000);
    } catch (err) { 
        console.log('\x1b[41m')
        console.clear();
        await fatalCrash(err);
        console.log('\x1b[0m')
    }
}

var balanceTKN;
var amountIn;
var amountOut;
var amountOutMin;
var token = {
    tokenName: "",
    tokenSymbol: "",
    tokenDecimals: undefined,
    totalSupply: undefined,
    maxTxAmount: undefined,
    maxBalance: undefined,
    pairAddress: ""
}

async function setupTx() {
    // Get token information
    await getTokenData();
    console.log(`  -INFO- ${token.tokenName}, ${token.tokenSymbol}, ${token.tokenDecimals}`)
    //console.log(`tokenSymbol:\t${token.tokenSymbol}`)
    //console.log(`tokenDecimals:\t${token.tokenDecimals}`)
    console.log(`  -INFO- ${token.totalSupply} total supply`)
    console.log(`  -INFO- ${token.maxTxAmount} max tx amount`)
    console.log(`  -INFO- ${token.maxBalance} max wallet balance`)
    //console.log(`pairAddress:\t${token.pairAddress}`)
    
    // Get current BNB & Token balance
    const balanceBNB = await getBalBNB();
    //console.log(`  -INFO- ${balanceBNB} BNB`)
    balanceTKN = await getBalToken();
    //console.log(`  -INFO- ${balanceTKN} ${token.tokenSymbol}`)
    console.log(`  -INFO- current balances ${balanceBNB} BNB, ${balanceTKN} ${token.tokenSymbol}`)
    
    //console.clear();
    //console.log(`${buildNumber}`);

    // Get rand BNB value
    amountIn = await getRandBNB(balanceBNB);
    console.log(`  -INFO- amountIn ${ethers.utils.formatEther(amountIn)} BNB`)

    // Figure out slippage and amounts
    const amounts = await router.getAmountsOut(amountIn, [tokenIn, tokenOut]);
    amountOut = amounts[1];
    console.log(`  -INFO- amountOut ${amountOut.toString()}`)
    const slip = (100 - data.Slippage);
    const slipCalc = (slip / 100) * amountOut;
    amountOutMin = BigNumber.from(parseInt(slipCalc).toFixed());
    //console.log(`amountOutMin:\t${amountOutMin.toString()}`)
}

async function doTx() {
    var receipt;
    let num = (Math.random()>=0.5)? 1 : 0;
    if (balanceTKN.gte(token.maxTxAmount.mul(2))) {
        console.log(`Selling ${token.tokenName}...`)
        let toSell = BigNumber.from(token.maxTxAmount);
        receipt = await sellToken(toSell);
    }
    else if ( token.maxBalance.lte(amountOut.add(balanceTKN)) && (amountOutMin.lte(balanceTKN)) ) {
        console.log(`Selling ${token.tokenName}...`)
        let toSell = BigNumber.from(amountOutMin.toString());
        receipt = await sellToken(toSell);
    }
    else {
        if ((amountOutMin.lte(balanceTKN)) && (num != 1)) {
            console.log(`Selling ${token.tokenName}...`)
            let toSell = BigNumber.from(amountOutMin.toString());
            receipt = await sellToken(toSell);
        }
        else {
            console.log(`Buying ${token.tokenName}...`)
            let toBuy = BigNumber.from(amountOutMin.toString());
            receipt = await buyToken(toBuy);
        }
    }
    console.log(`Transaction: https://testnet.bscscan.com/tx/${receipt.logs[1].transactionHash}`);
}

async function getBalBNB() {
    var balanceInEth
    const balance = await provider.getBalance(`${data.recipient}`).then((balance) => {
        balanceInEth = ethers.utils.formatEther(balance)
        })
    return balanceInEth;
}

async function getBalToken() {
    const currentBal = await tst.balanceOf(`${data.recipient}`);
    return currentBal;
}

async function setApproval() {
    const allowance = await tst.allowance(data.recipient, data.router)
    if (allowance.lt(token.totalSupply)) {
        await tst.approveMax(data.router);
    }
}

async function getTokenData() {
    try {
        token.tokenName = await tst.name();
    } catch (error) {}
    try {
        token.tokenSymbol = await tst.symbol();
    } catch (error) {}
    try {
        token.tokenDecimals = await tst.decimals();
    } catch (error) {
        token.tokenDecimals = 18;
    }
    try {
        token.totalSupply = await tst.totalSupply();
    } catch (error) {}
    try {
        //token.maxTxAmount = await tst._maxTxAmount();
        token.maxTxAmount = BigNumber.from("10000000000000000");
    } catch (error) {
        token.maxTxAmount = token.totalSupply;
    }
    try {
        token.maxBalance = await tst._maxBalance();
    } catch (error) {
        //token.maxBalance = token.totalSupply;
        token.maxBalance = BigNumber.from("100000000000000000");
    }
    try {
        token.pairAddress = await factory.getPair(tokenIn, tokenOut);
    } catch (error) {}
}

async function getRandBNB(balanceBNB) {

    var maxBNB
    const amount = await router.getAmountsIn(token.maxTxAmount, [tokenIn, tokenOut]).then((amount) => {
        maxBNB = ethers.utils.formatEther(amount[0])
        })
    //console.log(`Max Buy:\t${maxBNB.toString()} BNB`)
    if (maxBNB >= balanceBNB){
        maxBNB = balanceBNB;
    }
    const min = parseFloat(data.MIN_WBNB);
    const max = parseFloat(maxBNB);
    const randBNB = (Math.random() * (max - min) + min).toFixed(18);
    console.log(`  -INFO- amount selected ${randBNB} BNB`)
    const amountRnd = ethers.utils.parseEther(randBNB).toHexString();

    return amountRnd;
}

async function sellToken(toSell) {
    const tx = await router.swapExactTokensForETHSupportingFeeOnTransferTokens(
        toSell,
        0,
        [tokenOut, tokenIn],
        data.recipient,
        Date.now() + 1000 * 60 * 5, //5 minutes
        {
            'gasLimit': data.gasLimitSell,
            'gasPrice': data.gasPrice,
            'nonce' : null //set you want buy at where position in blocks
        });
        const receipt = await tx.wait();
        return receipt;
}

async function buyToken(toBuy) {
    const tx = await router.swapETHForExactTokens(
        //amountIn,
        toBuy,
        [tokenIn, tokenOut],
        data.recipient,
        Date.now() + 1000 * 60 * 5, //5 minutes
        {
            'gasLimit': data.gasLimit,
            'gasPrice': data.gasPrice,
            value: amountIn
        });
        const receipt = await tx.wait();
        return receipt;
}

async function fatalCrash(err) {
    let pimps1 = "failed to load tags for cache file";
    let pimps2 = "failed to load scenario 'levels\\multi\\riverworld\\riverworld";
    let pimps3 = "main_game_change_immediate() failed for 'levels\\multi\\riverworld\\riverworld', cannot load game";
    let pimps4 = "main game load failed, unable to recover, aboring to pregame";
    let error = JSON.parse(JSON.stringify(err));
    //console.log('\x1b[41m');
    console.log(`${buildNumber}`);
    console.log(`  -FATAL- ### ${error.reason.toUpperCase()}`);
    console.log(`  -FATAL- ${pimps1}`);
    console.log(`  -FATAL- ${pimps2}`);
    console.log(`  -FATAL- ${pimps3}`);
    console.log(`  -FATAL- ${pimps4}`);
    for (let i = 0; i < 18; i++) {
        console.log();
    }
    process.stdout.write('\x1b[0m');
    console.log('\x1b[0m');
    console.log()
    inquirer.prompt([
        {
          type: 'confirm',
          name: 'viewData',
          message: 'View error details',
        },
      ])
      .then(answers => {
        if(answers.viewData === true) {
          console.clear();
          console.log(error);
          process.exit();
        }
        else {
            run();
        }
    });
}

run();

const PORT = 5000;

app.listen(PORT);