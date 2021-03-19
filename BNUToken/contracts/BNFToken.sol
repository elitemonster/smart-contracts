pragma solidity ^0.7.1;

import "./core/Context.sol";
import "./libs/SafeMath.sol";
import "./core/ERC20Token.sol";
import "./interfaces/IBNFToken.sol";
import "./interfaces/IERC20Token.sol";

contract BNFToken is ERC20Token, IBNFToken {
    using SafeMath for uint;
    
    modifier onlyTokenSaleContract{
        require(_msgSender() == _tokenSaleContractAddress, "BNFToken: Only factory contract can process");
        _;
    }
    
    address public _tokenSaleContractAddress;
    uint public immutable _byteNextPercent = 20;
    address public _bnfSwapContractAddress;
    address public _byteNextFundAddress;
    
    address [] _holderAddresses;

    /**
     * @dev Generate token information
    */
    constructor (address byteNextFundAddress, address tokenSaleContractAddress) {
        name = 'ByteNext Fund';
        symbol = 'BNF';
        decimals = 18;
        _totalSupply = 0;
        
        _byteNextFundAddress = byteNextFundAddress;                                     //0x77f42723192B4e9D76f752F3404Fff46Dc535ade;
        _tokenSaleContractAddress = tokenSaleContractAddress;                           //0xA83D81113F57d63AF7EFDC4a12350365c7871266;
    }
    
    /**
     * @dev Set factory contract address
     */ 
    function setTokenSaleContractAddress(address contractAddress) external onlyOwner{
        _tokenSaleContractAddress = contractAddress;
    }
    
    /**
     * @dev Set BNF swap contract address
     */ 
    function setBNFSwapContractAddress(address contractAddress) external onlyOwner{
        _bnfSwapContractAddress = contractAddress;
    }
    
    /**
     * Token can not be transfered directly between holders
     */ 
    function transfer(address to, uint value) public pure override returns(bool){
        revert("The transfer function is disabled");
    }
    
    /**
     * @dev Token can only transfered between holders via swap contract
    */ 
    function transferFrom(address sender, address recipient, uint amount) public override returns(bool){
        require(_msgSender() == _bnfSwapContractAddress, "BNF token can be only transferred by BNF swap contract");
        return _transferFrom(sender, recipient, amount);
    }
    
    /**
     * @dev Create amount BNF token to account and increase totalSupply
     * 
     * Details: 
     *      When an investor purchases BNT token in seed or private round of token sale times,
     *      an new BNF token will be issued to make sure that investor's share
     *      Note that: ByteNext always takes _byteNextPercent of this funds 
     *      so that another BNF token amount will be also issued and added to ByteNext address
     * Implementations
     * 1. Make sure: This funtion can be only called from BNT token address and this contract should be active to process
     * 2. Validate account address
     * 3. Increase total supply of BNF token, issue more token and add to account address
     * 4. Add account to list of holders
     * 5. Calculate to issue token amount for ByteNext to make sure taking _byteNextPercent of this fund
     * 6. emit Event
     */ 
    function createShareHolder(address account, uint amount) external override onlyTokenSaleContract contractActive returns(bool){
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        
        if(!_isHolderExisted(account))
            _holderAddresses.push(account);
        
        _calculateByteNextBNF(amount);
        
        emit Transfer(address(0), account, amount);
        emit Issue(account, amount);
        return true;
    }
    
    /**
     * @dev Check whether holder exists or not
     */ 
    function _isHolderExisted(address account) internal view returns(bool){
        for(uint index = 0; index < _holderAddresses.length; index++){
            if(_holderAddresses[index] == account)
                return true;
        }
        return false;
    }
    
    /**
     * @dev Withdraw share
     * When an investors makes a withdrawal request, their BNF will be converted to ETH
     * Investors will pay token to take ETH
     * 
     * Implementations 
     * 1. Validate amount should be greater than or equals sender balance
     * 2. Calculate percentage of share holder to calculate ETH to pay
     * 3. Reduce sender token balance and token supply balance
     * 4. emit Event
     */
    function withdrawShare(uint amount) external returns(bool){
        address payable sender = payable(_msgSender());
        uint tokenBalance = _balances[sender];
        require(tokenBalance >= amount, "BNF token balance is not enough");
        
        uint ethBalance = address(this).balance;
        require(ethBalance > 0, "This fund has had no profit yet");

        uint ethReceive = amount.mul(ethBalance).div(_totalSupply);
        
        _totalSupply = _totalSupply.sub(amount);
        _balances[sender] = _balances[sender].sub(amount);

        sender.transfer(ethReceive);
        
        emit WithdrawShare(sender, amount);
        return true;
    }
    
    /**
     *@dev withdraw all ETH of this contract
     *
     * When all investors withdrawed 100% share,
     * the owner of contract can withdarw all ETH of this contract if ETH is transfered
     * 
     */ 
    function withdrawETH() external onlyOwner{
        require(_totalSupply == 0,"Can only withdraw all ETH when contract has no shareholder");
        uint balance = address(this).balance;
        require(balance > 0, "Balance is zero");
        
        msg.sender.transfer(balance);
        emit WithdrawETH(_msgSender(), balance);
    }
    
    /**
     * @dev 
     *      Pay profit for all shareholders base on shareholders' percentage and ETH balance percentage
     *      This function can be called any time
     * 
     * Implements
     * MAKE SURE: This function can be only called by contract's owner
     * 1. Validate ETH balance
     * 2. Calculate ETH to payProfit
     * 3. Calculate and pay annual profit for shareholders
     * 4. emit Event
     */ 
    function payAnnualProfit(uint percentage) external onlyOwner contractActive{
        require(percentage > 0 && percentage < 100, "Percentage should be greater than zero and less than 100");
        uint ethBalance = address(this).balance;
        require(ethBalance > 0, "Balance is zero");
        
        require(_holderAddresses.length > 0, "No shareholder found");
        
        uint totalEthToPay = ethBalance.mul(percentage).div(100);
        for(uint index = 0; index < _holderAddresses.length; index++){
            address holderAddress = _holderAddresses[index];
            uint ethToPay = _balances[holderAddress].mul(totalEthToPay).div(_totalSupply);
            
            payable(holderAddress).transfer(ethToPay);
        }
        
        emit PayAnnualProfit(_now());
    }

    /**
    * @dev Transfer BNF token from sender to recipient when sender transfers BNU token to recipient
    *
    * Implementations:
    *   1. Add recipent to shareholder list if does not exists
    *   2. Transfer `amount` BNF token from `sender` to `recipient`
    */
    function shareholderTransfer(address sender, address recipient, uint amount) external override onlyTokenSaleContract contractActive returns(bool){
        if(!_isHolderExisted(recipient))
            _holderAddresses.push(recipient);
        _transfer(sender, recipient, amount);
        return true;
    }
    
    /**
     * @dev Calculate ByteNext BNF amount when BNF token minted
     */
    function _calculateByteNextBNF(uint investAmount) internal{
        uint investorPercent = uint(100).sub(_byteNextPercent);
        
        //Calculate token to minted for ByteNext to remain _byteNextPercent%;
        uint amountToMint = investAmount.mul(_byteNextPercent).div(investorPercent);
        
        //Total supply
        _totalSupply = _totalSupply.add(amountToMint);
        _balances[_byteNextFundAddress] = _balances[_byteNextFundAddress].add(amountToMint);
        
        if(!_isHolderExisted(_byteNextFundAddress))
            _holderAddresses.push(_byteNextFundAddress);
        
        emit Issue(_byteNextFundAddress, amountToMint);
        emit Transfer(address(0), _byteNextFundAddress, amountToMint);
    }

    /**
    * @dev Enable to receive ETH
     */
    receive () external payable{}

    event Issue(address account, uint amount);
    event WithdrawShare(address account, uint amount);
    event WithdrawETH(address account, uint amount);
    event PayAnnualProfit(uint time);
}

//SPDX-License-Identifier: MIT