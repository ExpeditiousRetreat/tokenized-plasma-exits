pragma solidity ^0.4.0;

import "./SafeMath.sol";
import "./Math.sol";
import "./PlasmaRLP.sol";
import "./Merkle.sol";
import "./Validate.sol";
import "./PriorityQueue.sol";
import "./PlasmaToken.sol";


/**
 * @title RootChain
 * @dev This contract secures a utxo payments plasma child chain to ethereum.
 */
contract RootChain {
    using SafeMath for uint256;
    using Merkle for bytes32;
    using PlasmaRLP for bytes;


    /*
     * Events
     */

    event Deposit(
        address indexed depositor,
        uint256 indexed depositBlock,
        address token,
        uint256 amount
    );

    event ExitStarted(
        address indexed exitor,
        uint256 indexed utxoPos,
        address new_token,
        address token,
        uint256 amount
    );

    event BlockSubmitted(
        bytes32 root,
        uint256 timestamp
    );

    event TokenAdded(
        address token
    );


    /*
     * Storage
     */
    uint256 public constant EXIT_BOND = 1234567890;
    uint256 public constant CHILD_BLOCK_INTERVAL = 1000;
    address public constant ETHEREUM = address(0);

    address public operator;

    uint256 public currentChildBlock;
    uint256 public currentDepositBlock;
    uint256 public currentFeeExit;

    mapping (uint256 => PlasmaBlock) public plasmaBlocks;
    mapping (uint256 => Exit) public exits;
    mapping (address => address) public exitsQueues;
    address target;

    address[] openWithdrawals;
    mapping(address => uint) public openWithdrawalIndex;

    struct Exit {
        address owner;
        address token;
        address plasmaToken;
        uint256 amount;
    }

    struct PlasmaBlock {
        bytes32 root;
        uint256 timestamp;
    }


    /*
     * Modifiers
     */

    modifier onlyOperator() {
        require(msg.sender == operator, "Sender must be operator.");
        _;
    }

    modifier onlyWithValue(uint256 _value) {
        require(msg.value == _value, "Invalid attached value.");
        _;
    }


    /*
     * Constructor
     */

    constructor() public {
        operator = msg.sender;
        currentChildBlock = CHILD_BLOCK_INTERVAL;
        currentDepositBlock = 1;
        currentFeeExit = 1;
        // Support only ETH on deployment; other tokens need
        // to be added explicitly.
        
    }

    function setTarget(address _target) public {
        require(target == address(0));
        target = _target;
    }

    function setPriority(address _priority) public{
        require(exitsQueues[ETHEREUM]  == address(0));
        exitsQueues[ETHEREUM] = _priority;
    }


    /*
     * Public Functions
     */

    /**
     * @dev Allows Plasma chain operator to submit block root.
     * @param _root The root of a child chain block.
     */
    function submitBlock(bytes32 _root) public onlyOperator {
        plasmaBlocks[currentChildBlock] = PlasmaBlock({
            root: _root,
            timestamp: block.timestamp
        });

        // Update block numbers.
        currentChildBlock = currentChildBlock.add(CHILD_BLOCK_INTERVAL);
        currentDepositBlock = 1;

        emit BlockSubmitted(_root, block.timestamp);
    }

    /**
     * @dev Allows anyone to deposit funds into the Plasma chain.
     */
    function deposit() public payable {
        // Only allow up to CHILD_BLOCK_INTERVAL deposits per child block.
        require(currentDepositBlock < CHILD_BLOCK_INTERVAL, "Deposit limit reached.");

        bytes32 root = keccak256(abi.encodePacked(msg.sender, address(0), msg.value));
        uint256 depositBlock = getDepositBlock();
        plasmaBlocks[depositBlock] = PlasmaBlock({
            root: root,
            timestamp: block.timestamp
        });
        currentDepositBlock = currentDepositBlock.add(1);

        emit Deposit(msg.sender, depositBlock, ETHEREUM, msg.value);
    }

    event Print(uint _num);

    /**
     * @dev Starts an exit from a deposit.
     * @param _depositPos UTXO position of the deposit.
     * @param _token Token type to deposit.
     * @param _amount Deposit amount.
     */
    function startDepositExit(
        uint256 _depositPos,
        address _token,
        uint256 _amount
    )
        public payable onlyWithValue(EXIT_BOND)
    {
        uint256 blknum = _depositPos / 1000000000;
        require(blknum % CHILD_BLOCK_INTERVAL != 0, "Referenced block must be a deposit block.");
        bytes32 root = plasmaBlocks[blknum].root;
        bytes32 depositHash = keccak256(msg.sender, _token, _amount);
        require(root == depositHash, "Root hash must match deposit hash.");

        addExitToQueue(_depositPos, msg.sender, _token, _amount, plasmaBlocks[blknum].timestamp);
    }

    /**
     * @dev Allows the operator withdraw any allotted fees. Starts an exit to avoid theft.
     * @param _token Token to withdraw.
     * @param _amount Amount in fees to withdraw.
     */
    function startFeeExit(address _token, uint256 _amount) public payable onlyOperator onlyWithValue(EXIT_BOND) {
        addExitToQueue(currentFeeExit, msg.sender, _token, _amount, block.timestamp + 1);
        currentFeeExit = currentFeeExit.add(1);
    }

    /**
     * @dev Starts to exit a specified utxo.
     * @param _utxoPos The position of the exiting utxo in the format of blknum * 1000000000 + index * 10000 + oindex.
     * @param _txBytes The transaction being exited in RLP bytes format.
     * @param _proof Proof of the exiting transactions inclusion for the block specified by utxoPos.
     * @param _sigs Both transaction signatures and confirmations signatures used to verify that the exiting transaction has been confirmed.
     */
    function startExit(
        uint256 _utxoPos,
        bytes _txBytes,
        bytes _proof,
        bytes _sigs
    )
        public payable onlyWithValue(EXIT_BOND)
    {
        uint256 blknum = _utxoPos / 1000000000;
        uint256 txindex = (_utxoPos % 1000000000) / 10000;
        uint256 oindex = _utxoPos - blknum * 1000000000 - txindex * 10000;

        // Check the sender owns this UTXO.
        var exitingTx = _txBytes.createExitingTx(oindex);
        require(msg.sender == exitingTx.exitor, "Sender must be exitor.");

        // Check the transaction was included in the chain and is correctly signed.
        bytes32 root = plasmaBlocks[blknum].root;
        bytes32 merkleHash = keccak256(keccak256(_txBytes), ByteUtils.slice(_sigs, 0, 130));
        require(Validate.checkSigs(keccak256(_txBytes), root, exitingTx.inputCount, _sigs), "Signatures must match.");
        require(merkleHash.checkMembership(txindex, root, _proof), "Transaction Merkle proof is invalid.");

        addExitToQueue(_utxoPos, exitingTx.exitor, exitingTx.token, exitingTx.amount, plasmaBlocks[blknum].timestamp);
    }

    /**
     * @dev Allows anyone to challenge an exiting transaction by submitting proof of a double spend on the child chain.
     * @param _cUtxoPos The position of the challenging utxo.
     * @param _eUtxoIndex The output position of the exiting utxo.
     * @param _txBytes The challenging transaction in bytes RLP form.
     * @param _proof Proof of inclusion for the transaction used to challenge.
     * @param _sigs Signatures for the transaction used to challenge.
     * @param _confirmationSig The confirmation signature for the transaction used to challenge.
     */
    function challengeExit(
        uint256 _cUtxoPos,
        uint256 _eUtxoIndex,
        bytes _txBytes,
        bytes _proof,
        bytes _sigs,
        bytes _confirmationSig
    )
        public
    {
        uint256 eUtxoPos = _txBytes.getUtxoPos(_eUtxoIndex);
        uint256 txindex = (_cUtxoPos % 1000000000) / 10000;
        bytes32 root = plasmaBlocks[_cUtxoPos / 1000000000].root;
        bytes32 txHash = keccak256(_txBytes);
        bytes32 confirmationHash = keccak256(txHash, root);
        bytes32 merkleHash = keccak256(txHash, _sigs);
        address owner = exits[eUtxoPos].owner;

        // Validate the spending transaction.
        require(owner == ECRecovery.recover(confirmationHash, _confirmationSig), "Confirmation signature must be signed by owner.");
        require(merkleHash.checkMembership(txindex, root, _proof), "Transaction Merkle proof is invalid.");

        // Delete the owner but keep the amount to prevent another exit.
        delete exits[eUtxoPos].owner;
        msg.sender.transfer(EXIT_BOND);
    }

    /**
     * @dev Determines the next exit to be processed.
     * @param _token Asset type to be exited.
     * @return A tuple of the position and time when this exit can be processed.
     */
    function getNextExit(address _token) public view returns (uint256, uint256) {
        return PriorityQueue(exitsQueues[_token]).getMin();
    }


    event ExitFinal(address _seller,uint _paid);

    function finalizeExits(address _token, uint256 _withdrawalMax) public {
        uint256 utxoPos;
        uint256 exitableAt;
        require(ETHEREUM == _token, "Token must be ETH.");
        (exitableAt, utxoPos) = getNextExit(_token);
        exitableAt = 1;
        PriorityQueue queue = PriorityQueue(exitsQueues[_token]);
        Exit memory currentExit = exits[utxoPos];
        uint256 paid;
        while (exitableAt < block.timestamp && paid < _withdrawalMax) {
            paid++;
            currentExit = exits[utxoPos];
            PlasmaToken token = PlasmaToken(currentExit.plasmaToken);
            uint256 add_count = token.addressCount(); //We need to make it so this can't get too big
            uint256 balance;
            address holder;
            for(uint256 i=0;i<add_count;i++){
                (balance, holder) = token.getBalanceandHolderbyIndex(i);
                token.transferFrom(holder,address(0),balance);
                holder.transfer(balance);
            }
            popWithdrawal(currentExit.plasmaToken);
            if (currentExit.owner != address(0)) {
                currentExit.owner.transfer(EXIT_BOND);
            }
            queue.delMin();
            delete exits[utxoPos].owner;
            if (queue.currentSize() > 0) {
                (exitableAt,utxoPos) = getNextExit(_token);
            } else {
                return;
            }
        }
        emit ExitFinal(msg.sender,paid);
    }

    function popWithdrawal(address _token) internal {
        uint256 tokenIndex = openWithdrawalIndex[_token];
        uint256 lastTokenIndex = openWithdrawals.length.sub(1);
        address lastToken = openWithdrawals[lastTokenIndex];
        openWithdrawals[tokenIndex] = lastToken;
        openWithdrawalIndex[lastToken] = tokenIndex;
        openWithdrawals.length--;
    }


    /*
     * Public view functions
     */

    /**
     * @dev Queries the child chain.
     * @param _blockNumber Number of the block to return.
     * @return Child chain block at the specified block number.
     */
    function getPlasmaBlock(uint256 _blockNumber) public view returns (bytes32, uint256) {
        return (plasmaBlocks[_blockNumber].root, plasmaBlocks[_blockNumber].timestamp);
    }

    /**
     * @dev Determines the next deposit block number.
     * @return Block number to be given to the next deposit block.
     */
    function getDepositBlock() public view returns (uint256) {
        return currentChildBlock.sub(CHILD_BLOCK_INTERVAL).add(currentDepositBlock);
    }

    /**
     * @dev Returns information about an exit.
     * @param _utxoPos Position of the UTXO in the chain.
     * @return A tuple representing the active exit for the given UTXO.
     */
    function getExit(uint256 _utxoPos) public view returns (address, address, uint256) {
        return (exits[_utxoPos].owner, exits[_utxoPos].token, exits[_utxoPos].amount);
    }


    /*
     * Private functions
     */

    /**
     * @dev Adds an exit to the exit queue.
     * @param _utxoPos Position of the UTXO in the child chain.
     * @param _exitor Owner of the UTXO.
     * @param _token Token to be exited.
     * @param _amount Amount to be exited.
     * @param _created_at Time when the UTXO was created.
     */
    function addExitToQueue(
        uint256 _utxoPos,
        address _exitor,
        address _token,
        uint256 _amount,
        uint256 _created_at
    )
        private
    {
        // Check that we're exiting a known token.
        require(exitsQueues[_token] != address(0), "Must exit a known token.");

        // Check exit is valid and doesn't already exist.
        require(_amount > 0, "Exit value cannot be zero.");
        require(exits[_utxoPos].amount == 0, "Exit cannot already exist.");

        // Calculate priority.
        uint256 exitableAt = Math.max(_created_at + 2 weeks, block.timestamp + 1 weeks);
        PriorityQueue queue = PriorityQueue(exitsQueues[_token]);
        queue.insert(exitableAt, _utxoPos);
        address new_token = createClone();
        PlasmaToken Token = PlasmaToken(new_token);
        Token.init(_amount, msg.sender);

        exits[_utxoPos] = Exit({
            owner: _exitor,
            token: _token,
            plasmaToken: new_token,
            amount: _amount
        });
        
        openWithdrawalIndex[new_token] = openWithdrawals.length;
        openWithdrawals.push(new_token);
        emit ExitStarted(msg.sender, _utxoPos, new_token,_token, _amount);
    }

    /**
    *@dev Creates factory clone
    *@param _target is the address being cloned
    *@return address for clone
    */
    function createClone() internal returns (address result) {
        bytes memory clone = hex"600034603b57603080600f833981f36000368180378080368173bebebebebebebebebebebebebebebebebebebebe5af43d82803e15602c573d90f35b3d90fd";
        bytes20 targetBytes = bytes20(target);
        for (uint256 i = 0; i < 20; i++) {
            clone[26 + i] = targetBytes[i];
        }
        assembly {
            let len := mload(clone)
            let data := add(clone, 0x20)
            result := create(0, data, len)
        }
    }

//    function getUserBalance(address _owner, address _withdrawal) {
//        withdrawal = PlasmaToken(openWithdrawals[_withdrawal]);
//        return withdrawal.balanceOf[_owner];
//    }
}
