// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./standard/IERC20.sol";
import "./standard/IWTRX.sol";
import "./standard/IUniswapV2Router02.sol"; // Import your Uniswap-compatible DEX router contract

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
    
    IWTRX public WTRX; // TRX token contract address
    IJMSwapV2Router02 public dexRouter; // Uniswap-compatible DEX router contract

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
        address _WTRX,
        address _dexRouterAddress,
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

        WTRX = IWTRX(_WTRX);
        dexRouter = IJMSwapV2Router02(_dexRouterAddress);
  
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

    function calculateTrxToBuyIndexTokens(uint256 indexTokenAmount) public view returns (uint256[] memory) {
        uint256[] memory totalTrxAmount = new uint256[](underlyingTokenList.length);
        for (uint i = 0; i < underlyingTokenList.length; i++) {
            address token = underlyingTokenList[i];
            uint256 amount = underlyingTokens[token];

            if (amount > 0) {
                uint256 totalTokenAmount = (amount * indexTokenAmount) / (10**_decimals);
                address[] memory path = new address[](2);
                path[0] = address(WTRX);
                path[1] = token;
                uint256[] memory amountsOut = dexRouter.getAmountsIn(totalTokenAmount, path);
                totalTrxAmount[i] = amountsOut[0];
            }
        }
        return totalTrxAmount;
    }
    
    function calculateTrxAfterSellIndexTokens(uint256 indexTokenAmount) public view returns (uint256[] memory) {
        uint256[] memory totalTrxAmount = new uint256[](underlyingTokenList.length);
        
        for (uint i = 0; i < underlyingTokenList.length; i++) {
            address token = underlyingTokenList[i];
            uint256 amount = underlyingTokens[token];

            if (amount > 0) {
                uint256 totalTokenAmount = (amount * indexTokenAmount) / (10**_decimals);
                address[] memory path = new address[](2);
                path[0] = token;
                path[1] = address(WTRX);
                uint256[] memory amountsOut = dexRouter.getAmountsOut(totalTokenAmount, path);
                totalTrxAmount[i] = amountsOut[1];
            }
        }
        return totalTrxAmount;
    }
    
    function calculateTotalTrxToBuyIndexTokens(uint256 indexTokenAmount) public view returns (uint256) {
        uint256[] memory trxAmount = calculateTrxToBuyIndexTokens(indexTokenAmount);
        return sum(trxAmount);
    }
        
    function calculateTotalTrxAfterSellIndexTokens(uint256 indexTokenAmount) public view returns (uint256) {
        uint256[] memory trxAmount = calculateTrxAfterSellIndexTokens(indexTokenAmount);
        return sum(trxAmount);
    }
    
    //Deposit TRX and mint index tokens
    function mint(uint256 indexTokenAmount) payable external returns (uint256[] memory) {
        // Required TRX to buy indexTokens
        uint256[] memory requiredTrx = calculateTrxToBuyIndexTokens(indexTokenAmount);
        
        require(msg.value >= sum(requiredTrx), "Not enough TRX to mint the requested number of tokens");
    
        uint256[] memory amounts = new uint256[](underlyingTokenList.length);
        
        for (uint i = 0; i < underlyingTokenList.length; i++) {
            address token = underlyingTokenList[i];
            uint256 tokenAmount = underlyingTokens[token];
            uint256 totalTokenAmount = (tokenAmount * indexTokenAmount) / (10**_decimals);
            uint256 requiredTrxAmount = requiredTrx[i];

            // Swap TRX for underlying tokens 
            address[] memory path = new address[](2);
            path[0] = address(WTRX);
            path[1] = token;

            amounts[i] = dexRouter.swapTRXForExactTokens{value: requiredTrxAmount}(
                totalTokenAmount,
                path,
                address(this),
                block.timestamp
            )[0];
        }
        
        uint256 remainingTrx = msg.value - sum(amounts);
        require(remainingTrx >= 0, "Remaining TRX should always be greater than or equal to 0");
        
        // Mint indexTokens and return remainingTrx
        _mint(indexTokenAmount);
        payable(msg.sender).transfer(remainingTrx);
         
        // Emit an event to log the deposit
        emit Deposited(msg.sender, indexTokenAmount);
        return amounts;
    }

    // Redeem indexTokens for Trx 
    function redeem(uint256 indexTokenAmount, uint8 slippage) external returns (uint256[] memory) {
        require(_balanceOf[msg.sender] >= indexTokenAmount, "Insufficient redeemable balance");
        require(slippage >= 0 && slippage <= 10, "Slippage must be between 0 - 10 %");
        
        uint256[] memory amounts = new uint256[](underlyingTokenList.length);
        uint256[] memory expectedTrx = calculateTrxAfterSellIndexTokens(indexTokenAmount);
        
        for (uint i = 0; i < underlyingTokenList.length; i++) {
            address token = underlyingTokenList[i];
            uint256 tokenAmount = underlyingTokens[token];
            uint256 totalTokenAmount = (tokenAmount * indexTokenAmount) / (10**_decimals);
            uint256 minTrxAmount = (expectedTrx[i] * (100 - slippage))/100;
            
            // Swap underlying tokens for TRX 
            address[] memory path = new address[](2);
            path[0] = token;
            path[1] = address(WTRX);
            
            IERC20(token).approve(address(dexRouter), totalTokenAmount);

            uint256 amountsOut = dexRouter.swapExactTokensForTRX(
                totalTokenAmount,
                minTrxAmount, // Accept atleast this amount of Trx
                path,
                address(this),
                block.timestamp
            )[1];
            
            amounts[i] = amountsOut;
        }

        // Burn index tokens from the user's balance
        _balanceOf[msg.sender] -= indexTokenAmount;
        tokenTotalSupply -= indexTokenAmount;

        // Transfer TRX to the user
        payable(msg.sender).transfer(sum(amounts)); // Transfer the received TRX amount to the user
        
        // Emit an event to log the redemption
        emit Redeemed(msg.sender, indexTokenAmount);
        return amounts;
    }
    
    function sum(uint256[] memory numbers) internal pure returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < numbers.length; i++) {
            total += numbers[i];
        }
        return total;
    }

    function name() public view returns (string memory) {
        return tokenName;
    }

    function symbol() public view returns (string memory) {
        return tokenSymbol;
    }

    function image() public view returns (string memory) {
        return tokenImage;
    }

    function decimals() override external view returns (uint8) {
        return _decimals;
    }

    function getCreator() public view returns (address) {
        return owner;
    }

    function totalSupply() external view override returns (uint) {
        return tokenTotalSupply;
    }

    function balanceOf(address _owner) external view override returns (uint) {
        return _balanceOf[_owner];
    }

    function allowance(address _owner, address spender) external view override returns (uint) {
        return _allowance[_owner][spender];
    }

    function getUnderlyingTokenAmounts() public view returns (uint[] memory) {
        uint[] memory amounts = new uint[](underlyingTokenList.length);
        for (uint j = 0; j < underlyingTokenList.length; j++) {
            address token = underlyingTokenList[j];
            uint amount = underlyingTokens[token];
            amounts[j] = amount;
        }
        return amounts;
    }

    function getUnderlyingTokens() public view returns (address[] memory) {
        return underlyingTokenList;
    }

    function getTotalSupply() public view returns (uint){
        return tokenTotalSupply;
    }


    function transfer(address recipient, uint amount) external override returns (bool) {
        _balanceOf[tx.origin] -= amount;
        _balanceOf[recipient] += amount;

        //add to holders array
        holders.push(recipient);

        emit Transfer(tx.origin, recipient, amount);
        return true;
    }

    function approve(address spender, uint amount) external override returns (bool) {
        _allowance[tx.origin][spender] = amount;
        emit Approval(tx.origin, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external override returns (bool) {
        _allowance[sender][tx.origin] -= amount;
        _balanceOf[sender] -= amount;
        _balanceOf[recipient] += amount;

        //add to holders array
        holders.push(recipient);

        emit Transfer(sender, recipient, amount);
        return true;
    }

    function _mint(uint256 amount) internal {
        _balanceOf[tx.origin] += amount;
        tokenTotalSupply += amount;
        holders.push(tx.origin);

        emit Transfer(address(0), tx.origin, amount);
    }

    function burn(address burnee, uint256 amount) internal {
        _balanceOf[burnee] -= amount;
        tokenTotalSupply -= amount;
        emit Transfer(tx.origin, address(0), amount);
    }
}