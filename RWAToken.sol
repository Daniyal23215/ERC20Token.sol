# RWAToken.sol
//SPDX-License-Identifier:MIT

pragma solidity ^0.8.20;

/*
  Example: Real-World Asset Tokenization (Property)
  - 1 token = $1 share of the property
  - Total supply = 100,000 tokens
*/
contract RealEstateToken {
    string public name = "RealEstateToken";
    string public symbol = "RET";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    address public owner;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    struct  AssetDetails{
        string assetName;
        string assetLocation;
        uint256 assetValueUSD;
        string documentHash; // IPFS hash of legal property document

    }
    AssetDetails public asset;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

constructor()  {
    owner = msg.sender;
    totalSupply = 100000 * 10 ** uint256(decimals);
    balanceOf[msg.sender] = totalSupply;

    // Set property (RWA) metadata
    asset = AssetDetails({
        assetName: "Luxuxry Apaprtment",
        assetLocation: "DownTown Dubai",
        assetValueUSD: 100000,
        documentHash: "QmXoypizjW3WknFiJnKLwHCnL72vedxjQkDDP" // Example IPFS Hash

    });

}
    function transfer(address _to, uint256 _value) public returns (bool){
        require(balanceOf[msg.sender] >= _value, "Not enough tokens");
        balanceOf[msg.sender] -= _value;
        balanceOf[_to] += _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }
    
    
    function approve(address _spender, uint256 _value) public returns (bool) {
        allowance[msg.sender][_spender] =_value;
        emit Approval(msg.sender, _spender, _value);
        return true;
}
function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
    require(balanceOf[_from] >= _value, "Not enough balance");
    require(allowance[_from][msg.sender] >= _value, "Allowance too low");
    balanceOf[_from] -= _value;
    allowance[_from][msg.sender] -= _value;
    balanceOf[_to] += _value;
    emit Transfer(_from, _to, _value);
    return true;
}
function getAssetDetails() public view returns (AssetDetails memory) {
    return asset;
}
}

    

