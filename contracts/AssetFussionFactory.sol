// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./standard/Clones.sol";
import "./standard/Ownable.sol";
import "./AssetFussionIndexToken.sol";

contract AssetFussionFactory is Ownable {
    address public implementation;

    // Mapping to store the indexToken published by each creator
    mapping(address => address[]) public creatorToIndexToken;

    address[] public allIndexTokens;

    // Mapping to track used salts
    mapping(bytes32 => bool) public salts;

    constructor() Ownable(msg.sender) {
        // Set implementation contract.
        implementation = address(new AssetFussionIndexToken(address(this)));
    }
    
    function createIndexToken ( 
        address _WTRX,
        address _dexRouterAddress,
        address[] memory _underlyingTokens,
        uint256[] memory _underlyingTokensAmount,
        uint8[] memory _underlyingTokensDecimals,
        string memory _name,
        string memory _symbol,
        string memory _image,
        uint8 _tokenDecimals
    ) external returns (address clone) {
             // Generate a unique salt for deterministic deployment
            bytes32 salt = keccak256(abi.encodePacked(owner, _symbol));

            // Check if the salt has already been used
            require(!salts[salt], "Edition with the same salt already exists");

            // Mark the salt as used
            salts[salt] = true;

            // Use Clones.cloneDeterministic to create a new IndexToken clone
            clone = Clones.cloneDeterministic(implementation, salt);

            // Initialize with the provided parameters
            AssetFussionIndexToken(clone).initialize(msg.sender, _WTRX, _dexRouterAddress, _underlyingTokens, _underlyingTokensAmount, 
                                                    _underlyingTokensDecimals, _name, _symbol, _image, _tokenDecimals);

      
            creatorToIndexToken[msg.sender].push(clone);
            allIndexTokens.push(clone);

            return clone;
    }

    function getAllIndexTokens() public view returns (address[] memory) {
        return allIndexTokens;
    }

    function getAllIndexTokensFrom(address creator) public view returns (address[] memory) {
        return creatorToIndexToken[creator];
    }
}