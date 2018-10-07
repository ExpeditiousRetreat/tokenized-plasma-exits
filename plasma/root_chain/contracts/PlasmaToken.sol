pragma solidity ^0.4.18;

contract PlasmaToken {

    string public name     = "PlasmaToken";
    string public symbol   = "PT";
    uint8  public decimals = 18;
    address public withdrawalOwner;
    address public masterContract;
    uint public totalSupply;

    event  Approval(address indexed src, address indexed guy, uint wad);
    event  Transfer(address indexed src, address indexed dst, uint wad);
    event  Creation(address indexed dst, uint wad);

    mapping (address => mapping (address => uint))  public  allowance;
    mapping(address => uint) public balanceOf;
    address[] tokenHolders;
    mapping(address => uint) tokenHolderIndex;


    function() payable public{
        require(msg.value == 0);
    }

    function init(uint _amount,address _owner) {
        require (!isContract(_owner) && masterContract == address(0));
        balanceOf[_owner] += _amount;
        withdrawalOwner = _owner;
        masterContract = msg.sender;
        tokenHolderIndex[_owner] = tokenHolders.length;
        tokenHolders.push(_owner);
        totalSupply = _amount;
        emit Creation(_owner, _amount);
    }

    function totalSupply() public view returns (uint) {
        return address(this).balance;
    }

    function approve(address guy, uint wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        require(addressCount() < 128);//calculate what this number should be
        require(balanceOf[src] >= wad && !isContract(dst)) ;

        if (src != msg.sender && allowance[src][msg.sender] != uint(-1) && msg.sender!= masterContract) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        if(balanceOf[dst] == 0){
            tokenHolderIndex[dst] = tokenHolders.length;
            tokenHolders.push(dst);
        }
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        if(balanceOf[src]==0){
            uint tokenIndex = tokenHolderIndex[src];
            uint lastTokenIndex = tokenHolders.length - 1;
            address lastToken = tokenHolders[lastTokenIndex];
            tokenHolders[tokenIndex] = lastToken;
            tokenHolderIndex[lastToken] = tokenIndex;
            tokenHolders.length--;
        }

        emit Transfer(src, dst, wad);
        return true;
    }


    function getBalanceandHolderbyIndex(uint _index) public constant returns(uint _balance,address _holder){
        return(balanceOf[tokenHolders[_index]],tokenHolders[_index]);
    }

    function addressCount() public constant returns(uint _count){
        return tokenHolders.length;
    }

    function isContract(address _addr) internal returns (bool _isContract){
      uint32 size;
      assembly {
        size := extcodesize(_addr)
      }
      return (size > 0);
    }

}