 SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract DAppToken {

    string public name = "DApp Token";
    string public symbol = "DAPP";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    address public owner;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // Events required by ERC-20 standard
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 value
    );

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(uint256 initialSupply) {
        owner = msg.sender;
        totalSupply = initialSupply * 10**18;
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    // Transfer tokens
    function transfer(
        address recipient,
        uint256 amount
    ) public returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    // Approve spender
    function approve(
        address spender,
        uint256 amount
    ) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // Transfer on behalf of
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public returns (bool) {
        require(balanceOf[sender] >= amount, "Insufficient balance");
        require(
            allowance[sender][msg.sender] >= amount,
            "Allowance exceeded"
        );
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        allowance[sender][msg.sender] -= amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    // Owner can mint new tokens
    function mint(address recipient, uint256 amount) public {
        require(msg.sender == owner, "Not owner");
        totalSupply += amount * 10**18;
        balanceOf[recipient] += amount * 10**18;
        emit Transfer(address(0), recipient, amount * 10**18);
    }
}
