// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// ─────────────────────────────────────────────
//  DAPPToken — BlockpotDAO
//  Arbitrum Sepolia Testnet
//  Compiler : solc 0.8.20
//  Optimizer: OFF
// ─────────────────────────────────────────────

contract DAPPToken {

    // ── METADATA ─────────────────────────────
    string public name     = "DApp Token";
    string public symbol   = "DAPP";
    uint8  public decimals = 18;

    // ── STATE ─────────────────────────────────
    uint256 public totalSupply;
    address public owner;
    address public treasury;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ── EVENTS ────────────────────────────────
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

    event TreasurySet(
        address indexed treasury
    );

    // ── MODIFIERS ─────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(
            msg.sender == owner ||
            msg.sender == treasury,
            "Not authorized"
        );
        _;
    }

    // ── CONSTRUCTOR ───────────────────────────
    constructor(uint256 initialSupply) {
        owner = msg.sender;
        uint256 amount = initialSupply * 10 ** 18;
        totalSupply = amount;
        balanceOf[msg.sender] = amount;
        emit Transfer(address(0), msg.sender, amount);
    }

    // ── ERC-20 CORE ───────────────────────────
    function transfer(
        address recipient,
        uint256 amount
    ) public returns (bool) {
        require(
            balanceOf[msg.sender] >= amount,
            "Insufficient balance"
        );
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient]  += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(
        address spender,
        uint256 amount
    ) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public returns (bool) {
        require(
            balanceOf[sender] >= amount,
            "Insufficient balance"
        );
        require(
            allowance[sender][msg.sender] >= amount,
            "Allowance exceeded"
        );
        balanceOf[sender]                -= amount;
        balanceOf[recipient]             += amount;
        allowance[sender][msg.sender]    -= amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    // ── MINT ──────────────────────────────────
    // Called by Treasury to distribute rewards
    function mint(
        address recipient,
        uint256 amount
    ) public onlyAuthorized {
        totalSupply          += amount;
        balanceOf[recipient] += amount;
        emit Transfer(address(0), recipient, amount);
    }

    // ── BURN ──────────────────────────────────
    // Called when tokens are recycled into Treasury
    function burn(
        address from,
        uint256 amount
    ) public onlyAuthorized {
        require(
            balanceOf[from] >= amount,
            "Insufficient balance to burn"
        );
        balanceOf[from] -= amount;
        totalSupply     -= amount;
        emit Transfer(from, address(0), amount);
    }

    // ── ADMIN ─────────────────────────────────
    // Set Treasury address after deployment
    function setTreasury(
        address _treasury
    ) public onlyOwner {
        require(_treasury != address(0), "Zero address");
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    function transferOwnership(
        address newOwner
    ) public onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }
}
