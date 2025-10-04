# ERC20Token.sol
// SPDX-License-Identifier:MIT

pragma solidity ^0.8.20;

/// @title SimpleERC20 - Minimal ERC20 token with Ownable mint/burn
/// @notice Standalone implementation (no external imports) for quick deploy and learning
contract SimpleERC20 {

    // ERC basic data
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    // ownership
    address public owner;

    // Mappings for balances and allowances
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Events (ERC20)
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // Ownership Events
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Modifier  to restrict functions to owner only
    modifier onlyOwner() {
        require(msg.sender == owner, "SimpleERC20: caller is not the owner");
        _;
    }
/// @param _name Token name
    /// @param _symbol Token symbol
    /// @param _decimals Token decimals (commonly 18)
    /// @param _initialSupply Initial supply minted to deployer (in whole units, will be multiplied by 10**decimals)
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        owner = msg.sender;
        emit OwnershipTransferred(address (0), owner); 

        if (_initialSupply > 0) {
            uint256 scaled = _initialSupply * (10 ** uint256(_decimals));
            _mint(msg.sender, scaled);

            
        }
}
/// @notice Returns the balance of `account`
 function balanceOf(address account) external view returns (uint256) {
    return _balances[account];
}
/// @notice Transfer `amount` tokens to `recipient`
 function transfer(address recipient, uint256 amount) external returns (bool) {
    _transfer(msg.sender, recipient, amount);
    return true;
 }
 /// @notice Returns current allowance for `spender` by `tokenOwner`
    function allowance(address tokenOwner, address spender) external view returns (uint256) {
        return _allowances[tokenOwner][spender];
    }

    /// @notice Approve `spender` to spend `amount` on caller's behalf
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfer `amount` tokens from `sender` to `recipient` using allowance
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "SimpleERC20: transfer amount exceeds allowance");
        _approve(sender, msg.sender, currentAllowance - amount);
        _transfer(sender, recipient, amount);
        return true;
    }

    /// @notice Increase allowance for `spender`
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    /// @notice Decrease allowance for `spender`
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 current = _allowances[msg.sender][spender];
        require(current >= subtractedValue, "SimpleERC20: decreased allowance below zero");
        _approve(msg.sender, spender, current - subtractedValue);
        return true;
    }

    // --------------------
    // Owner-only functions
    // --------------------

    /// @notice Mint `amount` tokens to `account` (only owner)
    function mint(address account, uint256 amount) external onlyOwner returns (bool) {
        _mint(account, amount);
        return true;
    }

    /// @notice Burn `amount` tokens from caller's balance
    function burn(uint256 amount) external returns (bool) {
        _burn(msg.sender, amount);
        return true;
    }

    /// @notice Burn `amount` tokens from `account` using allowance (owner or approved)
    function burnFrom(address account, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[account][msg.sender];
        require(currentAllowance >= amount, "SimpleERC20: burn amount exceeds allowance");
        _approve(account, msg.sender, currentAllowance - amount);
        _burn(account, amount);
        return true;
    }

    /// @notice Transfer ownership to `newOwner`
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "SimpleERC20: new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // --------------------
    // Internal helpers
    // --------------------

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "SimpleERC20: transfer from the zero address");
        require(recipient != address(0), "SimpleERC20: transfer to the zero address");
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "SimpleERC20: transfer amount exceeds balance");

        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "SimpleERC20: mint to the zero address");

        totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "SimpleERC20: burn from the zero address");
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "SimpleERC20: burn amount exceeds balance");

        _balances[account] = accountBalance - amount;
        totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    function _approve(address tokenOwner, address spender, uint256 amount) internal {
        require(tokenOwner != address(0), "SimpleERC20: approve from the zero address");
        require(spender != address(0), "SimpleERC20: approve to the zero address");

        _allowances[tokenOwner][spender] = amount;
        emit Approval(tokenOwner, spender, amount);
    }
}
