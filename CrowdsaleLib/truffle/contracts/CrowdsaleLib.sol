pragma solidity ^0.4.15;

/**
 * @title CrowdsaleLib
 * @author Majoolr.io
 *
 * version 1.0.0
 * Copyright (c) 2017 Majoolr, LLC
 * The MIT License (MIT)
 * https://github.com/Majoolr/ethereum-libraries/blob/master/LICENSE
 *
 * The Crowdsale Library provides basic functionality to create an initial coin offering
 * for different types of token sales. 
 *
 * Majoolr works on open source projects in the Ethereum community with the
 * purpose of testing, documenting, and deploying reusable code onto the
 * blockchain to improve security and usability of smart contracts. Majoolr
 * also strives to educate non-profits, schools, and other community members
 * about the application of blockchain technology.
 * For further information: majoolr.io
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import "./BasicMathLib.sol";
import "./TokenLib.sol";
import "./CrowdsaleToken.sol";

library CrowdsaleLib {
  using BasicMathLib for uint256;

  struct CrowdsaleStorage {
  	address owner;     //owner of the crowdsale

  	uint256 tokensPerEth;  //number of tokens received per ether
    uint256 tokenPriceinCents;  // current price of token in cents (used to calculate token price from volatile price of ETH close to the sale)
  	uint256 capAmount; //Maximum amount to be raised in wei
  	uint256 startTime; //ICO start time, timestamp
  	uint256 endTime; //ICO end time, timestamp automatically calculated
    uint256 exchangeRate;   //  cents/ETH exchange rate at the time of the sale
    bool rateSet;


  	mapping (address => uint256) hasContributed;  //shows how much wei an address has contributed
  	mapping (address => uint256) withdrawTokensMap;  //For token withdraw function, maps a user address to the amount of tokens they can withdraw
    mapping (address => uint256) leftoverWei;       // any leftover wei that buyers contributed that didn't add up to a whole token amount

  	CrowdsaleToken token;
  }

  event LogTokensWithdrawn(address indexed _bidder, uint256 Amount);      // Indicates when an address has withdrawn their supply of tokens
  event LogWeiWithdrawn(address indexed _bidder, uint256 Amount);      // Indicates when an address has withdrawn their supply of extra wei
  event LogNoticeMsg(address _buyer, uint256 value, string Msg);          // Generic Notice message that includes and address and number
  event LogErrorMsg(string Msg);                                          // Indicates when an error has occurred in the execution of a function

  /// @dev Called by a crowdsale contract upon creation.
  /// @param self Stored crowdsale from crowdsale contract
  function init(CrowdsaleStorage storage self, 
                address _owner,
                uint256 _tokenPriceinCents,
                uint256 _fallbackExchangeRate,
                uint256 _capAmount,
                uint256 _startTime,
                uint256 _endTime,
                CrowdsaleToken _token) 
  {
  	require(self.capAmount == 0);
  	require(self.owner == 0);
    require(_endTime > _startTime);
    require(_tokenPriceinCents > 0);
    require(_capAmount > 0);
    require(_owner > 0);
    require(_startTime > now);
    require(_fallbackExchangeRate > 0);
    self.owner = _owner;
    self.tokenPriceinCents = _tokenPriceinCents;
    self.capAmount = _capAmount;
    self.startTime = _startTime;
    self.endTime = _endTime;
    self.exchangeRate = _fallbackExchangeRate;
    self.token = _token;
    changeTokenPrice(self,_tokenPriceinCents);
  }  

  /// @dev function to check if the crowdsale is currently active
  /// @param self Stored crowdsale from crowdsale contract
  /// @return success
  function crowdsaleActive(CrowdsaleStorage storage self) constant returns (bool) {
  	return (now >= self.startTime && now <= self.endTime);
  }

  /// @dev function to check if the crowdsale has ended
  /// @param self Stored crowdsale from crowdsale contract
  /// @return success
  function crowdsaleEnded(CrowdsaleStorage storage self) constant returns (bool) {
  	return now > self.endTime;
  }

  /// @dev function to check if a purchase is valid
  /// @param self Stored crowdsale from crowdsale contract
  /// @return true if the transaction can buy tokens
  function validPurchase(CrowdsaleStorage storage self) internal constant returns (bool) {
    bool nonZeroPurchase = msg.value != 0;
    if (crowdsaleActive(self) && nonZeroPurchase) {
      return true;
    } else {
      LogErrorMsg("Invalid Purchase! Check send time and amount of ether.");
      return false;
    }
  }

  /// @dev Function called by purchasers to pull tokens
  /// @param self Stored crowdsale from crowdsale contract
  function withdrawTokens(CrowdsaleStorage storage self) returns (bool) {
    if (self.withdrawTokensMap[msg.sender] == 0) {
      LogErrorMsg("Sender has no tokens to withdraw!");
      return false;
    }

    if ((msg.sender == self.owner) && (!crowdsaleEnded(self))) {
      LogErrorMsg("Owner cannot withdraw extra tokens until after the sale!");
      return false;
    }

    var total = self.withdrawTokensMap[msg.sender];
    self.withdrawTokensMap[msg.sender] = 0;
    bool ok = self.token.transfer(msg.sender, total);
    require(ok);
    LogTokensWithdrawn(msg.sender, total);
    return true;
  }

  /// @dev Function called by purchasers to pull leftover wei from their purchases
  /// @param self Stored crowdsale from crowdsale contract
  function withdrawLeftoverWei(CrowdsaleStorage storage self) returns (bool) {
    require(self.hasContributed[msg.sender] > 0);
    if (self.leftoverWei[msg.sender] == 0) {
      LogErrorMsg("Sender has no extra wei to withdraw!");
      return false;
    }

    var total = self.leftoverWei[msg.sender];
    self.leftoverWei[msg.sender] = 0;
    msg.sender.transfer(total);
    LogWeiWithdrawn(msg.sender, total);
    return true;
  }

  /// @dev Function to change the price of the token
  /// @param _newPrice new token price (amount of tokens per ether)
  function changeTokenPrice(CrowdsaleStorage storage self,uint256 _newPrice) internal returns (bool) {
  	require(_newPrice > 0);

    uint256 result;
    bool err;

    (err,result) = self.exchangeRate.dividedBy(_newPrice);
    require(!err);

  	self.tokensPerEth = result;
    return true;
  }

  /// @dev function that is called two days before the sale to set the token and price
  /// @param self Stored Crowdsale from crowdsale contract
  /// @param _exchangeRate  ETH exchange rate expressed in cents/ETH
  function setTokenExchangeRate(CrowdsaleStorage storage self, uint256 _exchangeRate) returns (bool) {
    require(msg.sender == self.owner);
    require((now > (self.startTime - 3 days)) && (now < (self.startTime)));
    require(!self.rateSet);   // the exchange rate can only be set once!
    require(self.token.balanceOf(this) > 0);

    self.withdrawTokensMap[msg.sender] = self.token.balanceOf(this);

    self.exchangeRate = _exchangeRate;
    changeTokenPrice(self,self.tokenPriceinCents);
    self.rateSet = true;

    LogNoticeMsg(msg.sender,self.tokensPerEth,"Owner has sent the exchange Rate and tokens bought per ETH!");
    return true;
  }

  /// @dev Gets the amount of ether that an account has contributed
  /// @param _buyer address to get the information for
  /// @return amount of ether 
  function getContribution(CrowdsaleStorage storage self, address _buyer) constant returns (uint256) {
    LogNoticeMsg(_buyer, self.hasContributed[_buyer], "Users ether contribution");
    return self.hasContributed[_buyer];
  }

  /// @dev returns the number of tokens that an account has purchased
  /// @param _buyer address to get the information for
  /// @return number of tokens the account can withdraw 
  function getTokenPurchase(CrowdsaleStorage storage self, address _buyer) constant returns (uint256) {
    LogNoticeMsg(_buyer, self.withdrawTokensMap[_buyer], "Users token purchase");
    return self.withdrawTokensMap[_buyer];
  }

  /// @dev returns the number of tokens that an account has purchased
  /// @param _buyer address to get the information for
  /// @return number of tokens the account can withdraw 
  function getLeftoverWei(CrowdsaleStorage storage self, address _buyer) constant returns (uint256) {
    LogNoticeMsg(_buyer, self.withdrawTokensMap[_buyer], "Users leftoverWei");
    return self.leftoverWei[_buyer];
  }
}