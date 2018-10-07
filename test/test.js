/** This contract tests the typical workflow from the dApp 
* (user contract, cash out)
*/
var RootChain= artifacts.require("./RootChain.sol");
var PlasmaToken = artifacts.require("./PlasmaToken.sol");
var PriorityQueue = artifacts.require("./PriorityQueue.sol");

function promisifyLogWatch(_event) {
  return new Promise((resolve, reject) => {
    _event.watch((error, log) => {
      _event.stopWatching();
      if (error !== null)
        reject(error);
      resolve(log);
    });
    });
}

contract('Mining Tests', function(accounts) {
  let rootChain;
  let plasmaToken;
  let priorityQ;
    let  BLKNUM_OFFSET = 1000000000
    let TXINDEX_OFFSET = 10000

    beforeEach('Setup contract for each test', async function () {
        rootChain = await RootChain.new();
        plasmaToken = await PlasmaToken.new();
        priorityQ = await PriorityQueue.new(rootChain.address);
        await rootChain.setTarget(plasmaToken.address);
        await rootChain.setPriority(priorityQ.address);
        console.log('Start the testPlasma.py!!')
    });
    it("Test Plasma Deposit", async function(){
        vars = await rootChain.deposit({value:1e18});
        assert(web3.fromWei(web3.eth.getBalance(rootChain.address), 'ether').toFixed(0) == 1);
    }); 




    it("Test Token Issuance", async function(){
        vars = await rootChain.deposit({from:accounts[1],value:1e18});
       // await rootChain.submitBlock(web3.toHex("Nick"),{from:accounts[0]});
        utxo_id = 1
        blknum = utxo_id // BLKNUM_OFFSET
        txindex =0
        oindex = 0
        utxo =  (blknum * BLKNUM_OFFSET) + (txindex * TXINDEX_OFFSET) + (oindex * 1)
        console.log(utxo);

        res = await rootChain.startDepositExit(utxo,"0x0000000000000000000000000000000000000000",1e18,{from:accounts[1],value:1234567890})
       console.log('res',res.logs[0].args)
        res = res.logs[0].args['new_token'];
        console.log('res2',res);
        plasmaToken = await PlasmaToken.at(res);
        console.log(await plasmaToken.balanceOf(accounts[1]))
        assert(await plasmaToken.balanceOf(accounts[1]) == 1e18);
    }); 
    it("Test Withdrawal No Transfers", async function(){
        vars = await rootChain.deposit({from:accounts[1],value:1e18});
       // await rootChain.submitBlock(web3.toHex("Nick"),{from:accounts[0]});
        utxo_id = 1
        blknum = utxo_id // BLKNUM_OFFSET
        txindex =0
        oindex = 0
        utxo =  (blknum * BLKNUM_OFFSET) + (txindex * TXINDEX_OFFSET) + (oindex * 1)
        console.log(utxo);

        res = await rootChain.startDepositExit(utxo,"0x0000000000000000000000000000000000000000",1e18,{from:accounts[1],value:1234567890})
       console.log('res',res.logs[0].args)
        res = res.logs[0].args['new_token'];
        console.log('res2',res);
        plasmaToken = await PlasmaToken.at(res);
        await rootChain.finalizeExits("0x0000000000000000000000000000000000000000",20)
        assert(await plasmaToken.balanceOf(accounts[1]) == 0);
    }); 
    // it("Test Two Withdrawals in one Final Exit", async function () {
    //     console.log('START MINING RIG!!');
    //     logNewValueWatcher = await promisifyLogWatch(oracletoken.NewValue({ fromBlock: 'latest' }));//or Event Mine?
    // });
    // it("Test 20 token holders", async function () {
    //     logMineWatcher = await promisifyLogWatch(oracletoken.Mine({ fromBlock: 'latest' }));//or Event Mine?
    //     assert(logMineWatcher.args._value > 0);
    // });
    // it("Test 10 token holders and five withdrawals in one final exit", async function () {
    //     for(var i = 0;i < 10;i++){
    //         logMineWatcher = await promisifyLogWatch(oracletoken.Mine({ fromBlock: 'latest' }));//or Event Mine?
    //         console.log('Mining...',i);
    //     }
    //     res = logMineWatcher.args._value;
    //     assert(res > 0);
    // });

});