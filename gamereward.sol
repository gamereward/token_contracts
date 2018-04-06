pragma solidity ^0.4.21;

contract owned {
    address public owner;

    function owned() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner) onlyOwner public {
        owner = newOwner;
    }
}

contract SafeMath {
  function safeMul(uint a, uint b) internal pure returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeDiv(uint a, uint b) internal pure returns (uint) {
    assert(b > 0);
    uint c = a / b;
    assert(a == b * c + a % b);
    return c;
  }

  function safeSub(uint a, uint b) internal pure returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function safeAdd(uint a, uint b) internal pure returns (uint) {
    uint c = a + b;
    assert(c>=a && c>=b);
    return c;
  }

  function max64(uint64 a, uint64 b) internal pure returns (uint64) {
    return a >= b ? a : b;
  }

  function min64(uint64 a, uint64 b) internal pure returns (uint64) {
    return a < b ? a : b;
  }

  function max256(uint256 a, uint256 b) internal pure returns (uint256) {
    return a >= b ? a : b;
  }

  function min256(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }
}

interface tokenRecipient { 
    function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) external; 
}

contract TokenERC20 is SafeMath{

    // Token information
    // Public variables of the token
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;


    // This creates an array with all balances
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;

    // This generates a public event on the blockchain that will notify clients
    event Transfer(address indexed from, address indexed to, uint256 value);

    // This notifies clients about the amount burnt
    event Burn(address indexed from, uint256 value);

    /**
     * Constrctor function
     *
     * Initializes contract with initial supply tokens to the creator of the contract
     */
    function TokenERC20(string _name, string _symbol, uint8 _decimals, uint256 _totalSupply) public {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _totalSupply * 10 ** uint256(decimals);
    }

    /**
     * Internal transfer, only can be called by this contract
     */
    function _transfer(address _from, address _to, uint _value) internal {
        // Prevent transfer to 0x0 address. Use burn() instead
        require(_to != 0x0);
        // Check if the sender has enough
        require(balanceOf[_from] >= _value);
        // Check for overflows
        require(balanceOf[_to] + _value > balanceOf[_to]);
        // Save this for an assertion in the future
        uint previousBalances = balanceOf[_from] + balanceOf[_to];
        // Subtract from the sender
        balanceOf[_from] -= _value;
        // Add the same to the recipient
        balanceOf[_to] += _value;
        emit Transfer(_from, _to, _value);
        // Asserts are used to use static analysis to find bugs in your code. They should never fail
        assert(balanceOf[_from] + balanceOf[_to] == previousBalances);
    }

    /**
     * Transfer tokens
     *
     * Send `_value` tokens to `_to` from your account
     *
     * @param _to The address of the recipient
     * @param _value the amount to send
     */
    function transfer(address _to, uint256 _value) public {
        _transfer(msg.sender, _to, _value);
    }

    /**
     * Transfer tokens from other address
     *
     * Send `_value` tokens to `_to` in behalf of `_from`
     *
     * @param _from The address of the sender
     * @param _to The address of the recipient
     * @param _value the amount to send
     */
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value <= allowance[_from][msg.sender]);     // Check allowance
        allowance[_from][msg.sender] -= _value;
        _transfer(_from, _to, _value);
        return true;
    }

    /**
     * Set allowance for other address
     *
     * Allows `_spender` to spend no more than `_value` tokens in your behalf
     *
     * @param _spender The address authorized to spend
     * @param _value the max amount they can spend
     */
    function approve(address _spender, uint256 _value) public
        returns (bool success) {
        allowance[msg.sender][_spender] = _value;
        return true;
    }

    /**
     * Set allowance for other address and notify
     *
     * Allows `_spender` to spend no more than `_value` tokens in your behalf, and then ping the contract about it
     *
     * @param _spender The address authorized to spend
     * @param _value the max amount they can spend
     * @param _extraData some extra information to send to the approved contract
     */
    function approveAndCall(address _spender, uint256 _value, bytes _extraData)
        public
        returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, this, _extraData);
            return true;
        }
    }

    /**
     * Destroy tokens
     *
     * Remove `_value` tokens from the system irreversibly
     *
     * @param _value the amount of money to burn
     */
    function burn(uint256 _value) public returns (bool success) {
        require(balanceOf[msg.sender] >= _value);   // Check if the sender has enough
        balanceOf[msg.sender] -= _value;            // Subtract from the sender
        totalSupply -= _value;                      // Updates totalSupply
        emit Burn(msg.sender, _value);
        return true;
    }

    /**
     * Destroy tokens from other account
     *
     * Remove `_value` tokens from the system irreversibly on behalf of `_from`.
     *
     * @param _from the address of the sender
     * @param _value the amount of money to burn
     */
    function burnFrom(address _from, uint256 _value) public returns (bool success) {
        require(balanceOf[_from] >= _value);                // Check if the targeted balance is enough
        require(_value <= allowance[_from][msg.sender]);    // Check allowance
        balanceOf[_from] -= _value;                         // Subtract from the targeted balance
        allowance[_from][msg.sender] -= _value;             // Subtract from the sender's allowance
        totalSupply -= _value;                              // Update totalSupply
        emit Burn(_from, _value);
        return true;
    }
}

/******************************************/
/*          GAMEREWARD TOKEN              */
/******************************************/

contract GameRewardToken is owned, TokenERC20 {

    // State machine
    enum State{PrivateFunding, PreFunding, Funding, Success, Failure}

    Funder[] public funders;

    mapping (address => bool) public frozenAccount;
    mapping (address => address) public applications;
    mapping (address => uint256) public bounties;
    mapping (address => uint256) public bonus;
    mapping (address => address) public referrals;

    /* This generates a public event on the blockchain that will notify clients */
    event FrozenFunds(address target, bool frozen);
    event MapParent(address target, address parent);
    event Fee(address from, address collector, uint fee);
    event FreeDistribution(uint256 number);
    event Refund(address to, uint256 value);
    event SetReferral(address target, address broker);
    event ChangeCampaign(uint256 fundingStartBlock, uint256 fundingEndBlock);
    event FundTransfer(address backer, uint amount, bool isContribution);
    event AddBounty(address bountyHunter, uint amount);
     // Crowdsale information
    bool public finalizedCrowdfunding = false;

    uint256 public fundingStartBlock = 0; // crowdsale start block
    uint256 public fundingEndBlock = 0; // crowdsale end block
    uint256 public constant lockedTokens =     250000000000000000000000000; //25% tokens to Vault and locked for 6 months - 250 millions
    uint256 public bonusAndBountyTokens =       50000000000000000000000000; //5% tokens for referral bonus and bounty - 50 millions
    uint256 public constant devsTokens =       100000000000000000000000000; //10% tokens for team - 100 millions
    uint256 public constant hundredPercent =                           100;
    uint256 public constant tokensPerEther =                      20000000; //GRD:ETH exchange rate - 20.000 GRD per ETH
    uint256 public constant tokenCreationMax = 600000000000000000000000000; //ICO hard target - 600 millions
    uint256 public constant tokenCreationMin =  60000000000000000000000000; //ICO soft target - 60 millions

    uint256 public constant tokenPrivateMax =  200000000000000000000000000; //Private-sale must stop when 100 millions tokens sold

    uint256 public constant minContributionAmount =     250000000000000000; //Backer must buy atleast 0.25ETH in open-sale
    uint256 public constant maxContributionAmount =  100000000000000000000; //Max 100 ETH in open-sale and pre-sale

    uint256 public constant minPrivateContribution =  50000000000000000000; //Backer must buy atleast 50ETH in private-sale
    uint256 public constant minPreContribution =       1000000000000000000; //Backer must buy atleast 1ETH in pre-sale

    uint256 public constant minAmountToGetBonus =      5000000000000000000; //Backer must buy atleast 5ETH to receive referral bonus
    uint256 public constant referralBonus =                              5; //5% for referral bonus
    uint256 public constant privateBonus =                              40; //40% bonus in private-sale
    uint256 public constant preBonus =                                  20; //20% bonus in pre-sale;

    uint256 public tokensSold;

    uint256 public constant numBlocksLocked = 1110857;  //180 days locked tokens
    uint256 public constant numBlocksBountyLocked = 40000; //7 days locked bounty tokens
    uint256 unlockedAtBlockNumber;

    address public lockedTokenHolder;
    address public releaseTokenHolder;
    address public devsHolder;


    /* data structure to hold information about campaign contributors */
    struct Funder {
        address addr;
        uint amount;
    }


    function GameRewardToken(
                        address _lockedTokenHolder,
                        address _releaseTokenHolder,
                        address _devsAddress
    ) TokenERC20("GameReward", // Name
                 "GRD",        // Symbol 
                  18,          // Decimals
                  1000000000   // Total Supply 1 Billion
                  ) public {
        
        require (_lockedTokenHolder != 0x0);
        require (_releaseTokenHolder != 0x0);
        require (_devsAddress != 0x0);
        lockedTokenHolder = _lockedTokenHolder;
        releaseTokenHolder = _releaseTokenHolder;
        devsHolder = _devsAddress;
    }

    /* Internal transfer, only can be called by this contract */
    function _transfer(address _from, address _to, uint _value) internal {
        require (getState() == State.Success);
        require (_to != 0x0);                               // Prevent transfer to 0x0 address. Use burn() instead
        require (balanceOf[_from] >= _value);               // Prevent transfer to 0x0 address. Use burn() instead
        require (safeAdd(balanceOf[_to],_value) > balanceOf[_to]); // Check for overflows
        require (!frozenAccount[_from]);                     // Check if sender is frozen
        require (!frozenAccount[_to]);                       // Check if recipient is frozen
        require (_from != lockedTokenHolder);
        balanceOf[_from] = safeSub(balanceOf[_from],_value);                        // Subtract from the sender
        balanceOf[_to] = safeAdd(balanceOf[_to],_value);                           // Add the same to the recipient
        emit Transfer(_from, _to, _value);
        if(applications[_to] != 0x0){
            balanceOf[_to] = safeSub(balanceOf[_to],_value);    
            balanceOf[applications[_to]] =safeAdd(balanceOf[applications[_to]],_value);    
            emit Transfer(_to, applications[_to], _value);
        }
    }

    ///@notice Application withdraw, only can be called by owner
    ///@param _from address of the sender
    ///@param _to address of the receiver
    ///@param _value the amount to send
    ///@param _fee the amount of transaction fee
    ///@param _collector address of collector to receive fee
    function withdraw(address _from, address _to, uint _value, uint _fee, address _collector) onlyOwner public {
        require (getState() == State.Success);
        require (applications[_from]!=0x0);                         // Check if sender have application
        address app = applications[_from];
        require (_collector != 0x0);
        require (_to != 0x0);                                   // Prevent transfer to 0x0 address. Use burn() instead
        require (balanceOf[app] >= safeAdd(_value, _fee));              // Prevent transfer to 0x0 address. Use burn() instead
        require (safeAdd(balanceOf[_to], _value)> balanceOf[_to]);     // Check for overflows
        require (!frozenAccount[app]);                          // Check if sender is frozen
        require (!frozenAccount[_to]);                          // Check if recipient is frozen
        require (_from != lockedTokenHolder);
        balanceOf[app] = safeSub(balanceOf[app],safeAdd(_value, _fee));                      // Subtract from the sender
        balanceOf[_to] = safeAdd(balanceOf[_to],_value);  
        balanceOf[_collector] = safeAdd(balanceOf[_collector], _fee); 
        emit Fee(app,_collector,_fee);
        emit Transfer(app, _collector, _fee);
        emit Transfer(app, _to, _value);
    }
    
    ///@notice map an address to its parent
    ///@param _target Address to set parent
    ///@param _parent Address of parent
    function setApplication(address _target, address _parent) onlyOwner public {
        require (getState() == State.Success);
        require(_parent!=0x0);
        applications[_target]=_parent;
        uint256 currentBalance=balanceOf[_target];
        emit MapParent(_target,_parent);
        if(currentBalance>0x0){
            balanceOf[_target] = safeDiv(balanceOf[_target],currentBalance);
            balanceOf[_parent] = safeAdd(balanceOf[_parent],currentBalance);
            emit Transfer(_target,_parent,currentBalance);
        }
    }

    /// @notice `freeze? Prevent | Allow` `target` from sending & receiving tokens
    /// @param _target Address to be frozen
    /// @param _freeze either to freeze it or not
    function freezeAccount(address _target, bool _freeze) onlyOwner public {
        frozenAccount[_target] = _freeze;
        emit FrozenFunds(_target, _freeze);
    }



    //Crowdsale Functions

    /// @notice get early bonus for backer
    function _getEarlyBonus() internal view returns(uint){
        if(getState()==State.PrivateFunding) return privateBonus;  
        else if(getState()==State.PreFunding) return preBonus; 
        else return 0;
    }

    /// @notice set start and end block for funding
    /// @param _fundingStartBlock start funding
    /// @param _fundingEndBlock  end funding
    function setCampaign(uint256 _fundingStartBlock, uint256 _fundingEndBlock) onlyOwner public{
        if(block.number < _fundingStartBlock){
            fundingStartBlock = _fundingStartBlock;
        }
        if(_fundingEndBlock > fundingStartBlock && _fundingEndBlock > block.number){
            fundingEndBlock = _fundingEndBlock;
        }
        emit ChangeCampaign(_fundingStartBlock,_fundingEndBlock);
    }


    /// @notice set Broker for Investor
    /// @param _target address of Investor
    /// @param _broker address of Broker
    function setReferral(address _target, address _broker) onlyOwner public {
        require (_target != 0x0);
        require (_broker != 0x0);
        referrals[_target] = _broker;
        emit SetReferral(_target, _broker);
    }

    /// @notice set token for bounty hunter to release when ICO success
    function addBounty(address _hunter, uint256 _amount) onlyOwner public{
        require(_hunter!=0x0);
        require(_amount<bonusAndBountyTokens);
        bounties[_hunter] = safeAdd(bounties[_hunter],_amount);
        bonusAndBountyTokens = safeSub(bonusAndBountyTokens,_amount);
        emit AddBounty(_hunter, _amount);
    }

    /// @notice Create tokens when funding is active. This fallback function require 90.000 gas or more
    /// @dev Required state: Funding
    /// @dev State transition: -> Funding Success (only if cap reached)
    function() payable public{
        // Abort if not in Funding Active state.
        // The checks are split (instead of using or operator) because it is
        // cheaper this way.
        // Do not allow creating 0 or more than the cap tokens.
        require (getState() != State.Success);
        require (getState() != State.Failure);
        require (msg.value != 0);

        if(getState()==State.PrivateFunding){
            require(msg.value>=minPrivateContribution);
        }else if(getState()==State.PreFunding){
            require(msg.value>=minPreContribution && msg.value < maxContributionAmount);
        }else if(getState()==State.Funding){
            require(msg.value==minContributionAmount && msg.value < maxContributionAmount);
        }

        // multiply by exchange rate to get newly created token amount
        uint256 createdTokens = safeMul(msg.value, tokensPerEther);
        uint256 brokerBonus = 0;
        uint256 earlyBonus = safeDiv(safeMul(createdTokens,_getEarlyBonus()),hundredPercent);

        createdTokens = safeAdd(createdTokens,earlyBonus);

        // don't go over the limit!
        if(getState()==State.PrivateFunding){
            require(safeAdd(tokensSold,createdTokens) <= tokenPrivateMax);
        }else{
            require (safeAdd(tokensSold,createdTokens) <= tokenCreationMax);
        }

        // we are creating tokens, so increase the totalSupply
        tokensSold = safeAdd(tokensSold, createdTokens);

        if(referrals[msg.sender]!= 0x0){
            brokerBonus = safeDiv(safeMul(createdTokens,referralBonus),hundredPercent);
            bonus[referrals[msg.sender]] = safeAdd(bonus[referrals[msg.sender]],brokerBonus);
        }


        funders[funders.length++] = Funder({addr: msg.sender, amount: msg.value});
        // Assign new tokens to the sender
        balanceOf[msg.sender] = safeAdd(balanceOf[msg.sender], createdTokens);

        // Log token creation event
        emit Transfer(0, msg.sender, createdTokens);
    }

    /// @notice send bonus token to broker
    function _releaseBonus() internal{
        for (uint i = 0; i < funders.length; ++i) {
            uint256 bonusAmount = bonus[funders[i].addr];
            require (bonusAmount<bonusAndBountyTokens);
            if(bonusAmount > 0 && funders[i].amount >= minAmountToGetBonus){
                balanceOf[funders[i].addr] = safeAdd(balanceOf[funders[i].addr],bonusAmount);
                bonusAndBountyTokens = safeSub(bonusAndBountyTokens,bonusAmount);
                emit Transfer(0,funders[i].addr,bonusAmount);
            }
        }
    }

    /// @notice send lockedTokens to devs address
    /// require State == Success
    /// require tokens unlocked
    function releaseLockedToken() external {
        require (getState() == State.Success);
        require (balanceOf[lockedTokenHolder] > 0x0);
        require (block.number >= unlockedAtBlockNumber);
        balanceOf[devsHolder] = safeAdd(balanceOf[devsHolder],balanceOf[lockedTokenHolder]);
        balanceOf[lockedTokenHolder] = 0;
        emit Transfer(lockedTokenHolder,devsHolder,balanceOf[lockedTokenHolder]);
    }
    
    /// @notice request to receive bounty tokens
    /// @dev require State == Succes
    function requestBounty() external{
        require(block.number > safeAdd(fundingEndBlock ,numBlocksBountyLocked)); //locked bounty hunter's token for 7 days after end of campaign
        require(getState()==State.Success);
        assert (bounties[msg.sender]>0);
        balanceOf[msg.sender] = safeAdd(balanceOf[msg.sender],bounties[msg.sender]);
        emit Transfer(0,msg.sender,bounties[msg.sender]);
    }

    /// @notice Finalize crowdfunding
    /// @dev If cap was reached or crowdfunding has ended then:
    /// create LUN for the Lunyr Multisig and developer,
    /// transfer ETH to the Lunyr Multisig address.
    /// @dev Required state: Success
    function finalizeCrowdfunding() external {
        // Abort if not in Funding Success state.
        require (getState() == State.Success); // don't finalize unless we won
        require (!finalizedCrowdfunding); // can't finalize twice (so sneaky!)

        // prevent more creation of tokens
        finalizedCrowdfunding = true;
        _releaseBonus();
        // Endowment: 30% of total goes to vault, timelocked for 6 months
        balanceOf[lockedTokenHolder] = safeAdd(balanceOf[lockedTokenHolder], lockedTokens);

        unlockedAtBlockNumber = block.number + numBlocksLocked;
        emit Transfer(0, lockedTokenHolder, lockedTokens);

        // Endowment: 10% of total goes to devs for marketing and bug bounty
        balanceOf[devsHolder] = safeAdd(balanceOf[devsHolder], devsTokens);
        emit Transfer(0, devsHolder, devsTokens);

        uint256 unSoldTokens = safeSub(tokenCreationMax,tokensSold);

        _freeDistribution(unSoldTokens);
        emit FreeDistribution(unSoldTokens);

        // Transfer ETH to the devs address.
        devsHolder.transfer(address(this).balance);
    }

    /// @notice send @param _unSoldTokens to all backer base on their share
    function _freeDistribution(uint256 _unSoldTokens) internal{
        for (uint i = 0; i < funders.length; ++i) {
            uint256 freeTokens = safeDiv(safeMul(_unSoldTokens,safeMul(funders[i].amount,tokensPerEther)),tokensSold);
            balanceOf[funders[i].addr] = safeAdd(balanceOf[funders[i].addr],freeTokens);
            emit Transfer(0,funders[i].addr, freeTokens);
        }  
    }

    /// @notice Get back the ether sent during the funding in case the funding
    /// has not reached the minimum level.
    /// @dev Required state: Failure
    function refund() external {
        // Abort if not in Funding Failure state.
        assert (getState() == State.Failure);
        for (uint i = 0; i < funders.length; ++i) {
            funders[i].addr.transfer(funders[i].amount);  
            emit Refund(funders[i].addr, funders[i].amount);
        }      
    }

    /// @notice This manages the crowdfunding state machine
    /// We make it a function and do not assign the result to a variable
    /// So there is no chance of the variable being stale
    function getState() public constant returns (State){
      // once we reach success, lock in the state
      if (finalizedCrowdfunding) return State.Success;
      if(fundingStartBlock ==0 && fundingEndBlock==0) return State.PrivateFunding;
      else if (block.number < fundingStartBlock) return State.PreFunding;
      else if (block.number <= fundingEndBlock && tokensSold < tokenCreationMax) return State.Funding;
      else if (tokensSold >= tokenCreationMin) return State.Success;
      else return State.Failure;
    }

}
