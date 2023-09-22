// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./standard/IERC20.sol";
import "./standard/IWTRX.sol";

contract AssetFussionIndexToken is IERC20 {
    address public owner;
    uint public tokenTotalSupply;
    mapping(address => uint256) public _balanceOf;
    mapping(address => mapping(address => uint256)) public _allowance;

    // Token Details
    string public tokenName;
    string public tokenSymbol;
    string public tokenImage;

    uint8 public  _decimals;

    /// @notice Address that deploys and initializes clones.
    address public immutable factory;
    

    mapping(address => uint256) public userDeposits; // User deposits
    address[] public holders;

    // Mapping of underlying tokens and their ratios in the index
    mapping(address => uint256) public underlyingTokens;
    mapping(address => uint8) public underlyingTokensDecimals;
    address[] public underlyingTokenList;
    
    event Deposited(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);

    function initialize( 
        address _owner,
        address[] memory _underlyingTokens,
        uint256[] memory _underlyingTokensAmount,
        uint8[] memory _underlyingTokensDecimals,
        string memory _name,
        string memory _symbol,
        string memory _image,
        uint8 _tokenDecimals
    ) external {
        // Only factory can call this function.
        require(msg.sender == factory, "Unauthorized caller");

        owner = _owner;

        tokenName = _name;
        tokenSymbol = _symbol;
        tokenImage = _image;
        _decimals = _tokenDecimals;

        
        require(_underlyingTokens.length > 0, "No underlying tokens defined");
        require(_underlyingTokens.length == _underlyingTokensAmount.length, "Invalid input arrays");
        require(_underlyingTokens.length == _underlyingTokensDecimals.length, "Invalid input arrays");
        
        // Tnitialise the contract
        for (uint i = 0; i < _underlyingTokens.length; i++) {
            underlyingTokens[_underlyingTokens[i]] = _underlyingTokensAmount[i];
            underlyingTokensDecimals[_underlyingTokens[i]] = _underlyingTokensDecimals[i];
            underlyingTokenList.push(_underlyingTokens[i]);
        }
    }

    constructor(address _factory) {
        require(_factory != address(0), "must set factory");
        factory = _factory;
    }

    modifier onlyOwner(){
        require(msg.sender == owner);
        _;
    }

    //Deposit TRX and mint index tokens
    function mint(uint256 indexTokenAmount) payable external returns (uint256[] memory) {
        
    }

    // Redeem indexTokens for Trx 
    function redeem(uint256 indexTokenAmount, uint8 slippage) external returns (uint256[] memory) {
       
}