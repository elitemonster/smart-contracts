pragma solidity ^0.7.1;

/**
 * @title Context
 * @dev Provide context functions
 */
abstract contract Context {
    address public owner;                   //Contract owner address
    bool public isContractActive;           //Make sure this contract can be used or not
    address internal _requestingOwner;
    /**
     * Make sure the sender is the owner of contract
     */ 
    modifier onlyOwner{
        require(_msgSender() == owner, "Only owner can process");
        _;
    }
    
    /**
     * Make sure the contract is active to execute
    */ 
    modifier contractActive{
        require(isContractActive, "This contract is deactived");
        _;
    }

    /**
    * @dev Constructor
    * 
    * Implementations:
    *   1. Set the owner of contract
    *   2. Set contract is active
    */
    constructor(){
       owner = _msgSender();           //Set owner address when contract is created
       isContractActive = true;        //Contract is active when it is created
    }

    /**
     * Get sender address
     */ 
    function _msgSender() internal view returns(address){
        return msg.sender;
    }

    /**
     * Get current time in unix timestamp
     */
    function _now() internal view returns(uint){
        return block.timestamp;
    }

    /**
    * Update contract status to make sure this contract can be executed or not
     */
    function toggleContractStatus() external onlyOwner{
        isContractActive = !isContractActive;
    }

    /**
    * @dev Return the new owner address is being requested
    */
    function requestingOwner() external view returns(address){
        return _requestingOwner;
    }

    /**
    * @dev Request to transfer ownership for contract
    * @return If success return true; else return false
    * 
    * Requirements:
    *   1. Only current owner can execute
    *   2. `newOwner` is not zero address
    *   3. `newOwner` is not current owner
    * 
    * Implementations:
    *   1. Validate requirements
    *   2. Set _requestingOwner is newOwner
    *   3. Return result
    */
    function requestNewOwner(address newOwner) external onlyOwner returns(bool){
        require(newOwner != address(0), "New owner is zero address");
        require(newOwner != owner, "New owner is current owner");

        _requestingOwner = newOwner;
        return true;
    }

    /**
    * @dev New requesting owner approves to being new contract's owner
     */
    function approveNewOwner() external{
        require(_requestingOwner != address(0), "New requesting owner is not initialized");
        require(_msgSender() == _requestingOwner, "Forbidden");
        owner = _requestingOwner;
        _requestingOwner = address(0);

        emit OwnerChanged(owner);
    }

    /**
    * @dev Event that notifies contract's owner has been changed to `newOwner` 
    */
    event OwnerChanged(address newOwner);
}

//SPDX-License-Identifier: MIT