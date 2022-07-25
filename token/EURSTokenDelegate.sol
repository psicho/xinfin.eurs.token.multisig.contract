/*
 * EURS Token Smart Contract.
 * Copyright (c) 2018 by STSS (Malta) Limited.
 * Contact: <tech@stasis.net>
 */
pragma solidity ^0.4.20;

import "./AbstractToken.sol";

/**
 * EURS Token Smart Contract: EIP-20 compatible token smart contract that
 * manages EURS tokens.
 */
contract EURSToken is AbstractToken {
  /**
   * Fee denominator (0.001%).
   */
  uint256 constant internal FEE_DENOMINATOR = 100000;

  /**
   * Maximum fee numerator (100%).
   */
  uint256 constant internal MAX_FEE_NUMERATOR = FEE_DENOMINATOR;

  /**
   * Minimum fee numerator (0%).
   */
  uint256 constant internal MIN_FEE_NUMERATIOR = 0;

  /**
   * Maximum allowed number of tokens in circulation.
   */
  uint256 constant internal MAX_TOKENS_COUNT =
    0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff /
    MAX_FEE_NUMERATOR;

  /**
   * Default transfer fee.
   */
  uint256 constant internal DEFAULT_FEE = 5e2;

  /**
   * Address flag that marks black listed addresses.
   */
  uint256 constant internal BLACK_LIST_FLAG = 0x01;

  /**
   * Address flag that marks zero fee addresses.
   */
  uint256 constant internal ZERO_FEE_FLAG = 0x02;

  modifier delegatable {
    if (delegate == address (0)) {
      require (msg.value == 0); // Non payable if not delegated
      _;
    } else {
      assembly {
        // Save owner
        let oldOwner := sload (owner_slot)

        // Save delegate
        let oldDelegate := sload (delegate_slot)

        // Solidity stores address of the beginning of free memory at 0x40
        let buffer := mload (0x40)

        // Copy message call data into buffer
        calldatacopy (buffer, 0, calldatasize)

        // Lets call our delegate
        let result := delegatecall (gas, oldDelegate, buffer, calldatasize, buffer, 0)

        // Check, whether owner was changed
        switch eq (oldOwner, sload (owner_slot))
        case 1 {} // Owner was not changed, fine
        default {revert (0, 0) } // Owner was changed, revert!

        // Check, whether delegate was changed
        switch eq (oldDelegate, sload (delegate_slot))
        case 1 {} // Delegate was not changed, fine
        default {revert (0, 0) } // Delegate was changed, revert!

        // Copy returned value into buffer
        returndatacopy (buffer, 0, returndatasize)

        // Check call status
        switch result
        case 0 { revert (buffer, returndatasize) } // Call failed, revert!
        default { return (buffer, returndatasize) } // Call succeeded, return
      }
    }
  }

  /**
   * Create EURS Token smart contract with message sender as an owner.
   *
   * @param _feeCollector address fees are sent to
   */
  function EURSToken (address _feeCollector) public {
    fixedFee = DEFAULT_FEE;
    minVariableFee = 0;
    maxVariableFee = 0;
    variableFeeNumerator = 0;

    owner = msg.sender;
    feeCollector = _feeCollector;
  }

  /**
   * Delegate unrecognized functions.
   */
  function () public delegatable payable {
    revert (); // Revert if not delegated
  }

  /**
   * Get name of the token.
   *
   * @return name of the token
   */
  function name () public delegatable view returns (string) {
    return "STASIS EURS Token";
  }

  /**
   * Get symbol of the token.
   *
   * @return symbol of the token
   */
  function symbol () public delegatable view returns (string) {
    return "EURS";
  }

  /**
   * Get number of decimals for the token.
   *
   * @return number of decimals for the token
   */
  function decimals () public delegatable view returns (uint8) {
    return 2;
  }

  /**
   * Get total number of tokens in circulation.
   *
   * @return total number of tokens in circulation
   */
  function totalSupply () public delegatable view returns (uint256) {
    return tokensCount;
  }

  /**
   * Get number of tokens currently belonging to given owner.
   *
   * @param _owner address to get number of tokens currently belonging to the
   *        owner of
   * @return number of tokens currently belonging to the owner of given address
   */
  function balanceOf (address _owner)
    public delegatable view returns (uint256 balance) {
    return AbstractToken.balanceOf (_owner);
  }

  /**
   * Transfer given number of tokens from message sender to given recipient.
   *
   * @param _to address to transfer tokens to the owner of
   * @param _value number of tokens to transfer to the owner of given address
   * @return true if tokens were transferred successfully, false otherwise
   */
  function transfer (address _to, uint256 _value)
  public delegatable payable returns (bool) {
    if (frozen) return false;
    else if (
      (addressFlags [msg.sender] | addressFlags [_to]) & BLACK_LIST_FLAG ==
      BLACK_LIST_FLAG)
      return false;
    else {
      uint256 fee =
        (addressFlags [msg.sender] | addressFlags [_to]) & ZERO_FEE_FLAG == ZERO_FEE_FLAG ?
          0 :
          calculateFee (_value);

      if (_value <= accounts [msg.sender] &&
          fee <= safeSub (accounts [msg.sender], _value)) {
        require (AbstractToken.transfer (_to, _value));
        require (AbstractToken.transfer (feeCollector, fee));
        return true;
      } else return false;
    }
  }

  /**
   * Transfer given number of tokens from given owner to given recipient.
   *
   * @param _from address to transfer tokens from the owner of
   * @param _to address to transfer tokens to the owner of
   * @param _value number of tokens to transfer from given owner to given
   *        recipient
   * @return true if tokens were transferred successfully, false otherwise
   */
  function transferFrom (address _from, address _to, uint256 _value)
  public delegatable payable returns (bool) {
    if (frozen) return false;
    else if (
      (addressFlags [_from] | addressFlags [_to]) & BLACK_LIST_FLAG ==
      BLACK_LIST_FLAG)
      return false;
    else {
      uint256 fee =
        (addressFlags [_from] | addressFlags [_to]) & ZERO_FEE_FLAG == ZERO_FEE_FLAG ?
          0 :
          calculateFee (_value);

      if (_value <= allowances [_from][msg.sender] &&
          fee <= safeSub (allowances [_from][msg.sender], _value) &&
          _value <= accounts [_from] &&
          fee <= safeSub (accounts [_from], _value)) {
        require (AbstractToken.transferFrom (_from, _to, _value));
        require (AbstractToken.transferFrom (_from, feeCollector, fee));
        return true;
      } else return false;
    }
  }

  /**
   * Allow given spender to transfer given number of tokens from message sender.
   *
   * @param _spender address to allow the owner of to transfer tokens from
   *        message sender
   * @param _value number of tokens to allow to transfer
   * @return true if token transfer was successfully approved, false otherwise
   */
  function approve (address _spender, uint256 _value)
  public delegatable payable returns (bool success) {
    return AbstractToken.approve (_spender, _value);
  }

  /**
   * Tell how many tokens given spender is currently allowed to transfer from
   * given owner.
   *
   * @param _owner address to get number of tokens allowed to be transferred
   *        from the owner of
   * @param _spender address to get number of tokens allowed to be transferred
   *        by the owner of
   * @return number of tokens given spender is currently allowed to transfer
   *         from given owner
   */
  function allowance (address _owner, address _spender)
  public delegatable view returns (uint256 remaining) {
    return AbstractToken.allowance (_owner, _spender);
  }

  /**
   * Transfer given number of token from the signed defined by digital signature
   * to given recipient.
   *
   * @param _to address to transfer token to the owner of
   * @param _value number of tokens to transfer
   * @param _fee number of tokens to give to message sender
   * @param _nonce nonce of the transfer
   * @param _v parameter V of digital signature
   * @param _r parameter R of digital signature
   * @param _s parameter S of digital signature
   */
  function delegatedTransfer (
    address _to, uint256 _value, uint256 _fee,
    uint256 _nonce, uint8 _v, bytes32 _r, bytes32 _s)
  public delegatable payable returns (bool) {
    if (frozen) return false;
    else {
      address _from = ecrecover (
        keccak256 (
          thisAddress (), messageSenderAddress (), _to, _value, _fee, _nonce),
        _v, _r, _s);

      if (_nonce != nonces [_from]) return false;

      if (
        (addressFlags [_from] | addressFlags [_to]) & BLACK_LIST_FLAG ==
        BLACK_LIST_FLAG)
        return false;

      uint256 fee =
        (addressFlags [_from] | addressFlags [_to]) & ZERO_FEE_FLAG == ZERO_FEE_FLAG ?
          0 :
          calculateFee (_value);

      uint256 balance = accounts [_from];
      if (_value > balance) return false;
      balance = safeSub (balance, _value);
      if (fee > balance) return false;
      balance = safeSub (balance, fee);
      if (_fee > balance) return false;
      balance = safeSub (balance, _fee);

      nonces [_from] = _nonce + 1;

      accounts [_from] = balance;
      accounts [_to] = safeAdd (accounts [_to], _value);
      accounts [feeCollector] = safeAdd (accounts [feeCollector], fee);
      accounts [msg.sender] = safeAdd (accounts [msg.sender], _fee);

      Transfer (_from, _to, _value);
      Transfer (_from, feeCollector, fee);
      Transfer (_from, msg.sender, _fee);

      return true;
    }
  }

  /**
   * Create tokens.
   *
   * @param _value number of tokens to be created.
   */
  function createTokens (uint256 _value)
  public delegatable payable returns (bool) {
    require (msg.sender == owner);

    if (_value > 0) {
      if (_value <= safeSub (MAX_TOKENS_COUNT, tokensCount)) {
        accounts [msg.sender] = safeAdd (accounts [msg.sender], _value);
        tokensCount = safeAdd (tokensCount, _value);

        Transfer (address (0), msg.sender, _value);

        return true;
      } else return false;
    } else return true;
  }

  /**
   * Burn tokens.
   *
   * @param _value number of tokens to burn
   */
  function burnTokens (uint256 _value)
  public delegatable payable returns (bool) {
    require (msg.sender == owner);

    if (_value > 0) {
      if (_value <= accounts [msg.sender]) {
        accounts [msg.sender] = safeSub (accounts [msg.sender], _value);
        tokensCount = safeSub (tokensCount, _value);

        Transfer (msg.sender, address (0), _value);

        return true;
      } else return false;
    } else return true;
  }

  /**
   * Freeze token transfers.
   */
  function freezeTransfers () public delegatable payable {
    require (msg.sender == owner);

    if (!frozen) {
      frozen = true;

      Freeze ();
    }
  }

  /**
   * Unfreeze token transfers.
   */
  function unfreezeTransfers () public delegatable payable {
    require (msg.sender == owner);

    if (frozen) {
      frozen = false;

      Unfreeze ();
    }
  }

  /**
   * Set smart contract owner.
   *
   * @param _newOwner address of the new owner
   */
  function setOwner (address _newOwner) public {
    require (msg.sender == owner);

    owner = _newOwner;
  }

  /**
   * Set fee collector.
   *
   * @param _newFeeCollector address of the new fee collector
   */
  function setFeeCollector (address _newFeeCollector)
  public delegatable payable {
    require (msg.sender == owner);

    feeCollector = _newFeeCollector;
  }

  /**
   * Get current nonce for token holder with given address, i.e. nonce this
   * token holder should use for next delegated transfer.
   *
   * @param _owner address of the token holder to get nonce for
   * @return current nonce for token holder with give address
   */
  function nonce (address _owner) public view delegatable returns (uint256) {
    return nonces [_owner];
  }

  /**
   * Set fee parameters.
   *
   * @param _fixedFee fixed fee in token units
   * @param _minVariableFee minimum variable fee in token units
   * @param _maxVariableFee maximum variable fee in token units
   * @param _variableFeeNumerator variable fee numerator
   */
  function setFeeParameters (
    uint256 _fixedFee,
    uint256 _minVariableFee,
    uint256 _maxVariableFee,
    uint256 _variableFeeNumerator) public delegatable payable {
    require (msg.sender == owner);

    require (_minVariableFee <= _maxVariableFee);
    require (_variableFeeNumerator <= MAX_FEE_NUMERATOR);

    fixedFee = _fixedFee;
    minVariableFee = _minVariableFee;
    maxVariableFee = _maxVariableFee;
    variableFeeNumerator = _variableFeeNumerator;

    FeeChange (
      _fixedFee, _minVariableFee, _maxVariableFee, _variableFeeNumerator);
  }

  /**
   * Get fee parameters.
   *
   * @return fee parameters
   */
  function getFeeParameters () public delegatable view returns (
    uint256 _fixedFee,
    uint256 _minVariableFee,
    uint256 _maxVariableFee,
    uint256 _variableFeeNumnerator) {
    _fixedFee = fixedFee;
    _minVariableFee = minVariableFee;
    _maxVariableFee = maxVariableFee;
    _variableFeeNumnerator = variableFeeNumerator;
  }

  /**
   * Calculate fee for transfer of given number of tokens.
   *
   * @param _amount transfer amount to calculate fee for
   * @return fee for transfer of given amount
   */
  function calculateFee (uint256 _amount)
    public delegatable view returns (uint256 _fee) {
    require (_amount <= MAX_TOKENS_COUNT);

    _fee = safeMul (_amount, variableFeeNumerator) / FEE_DENOMINATOR;
    if (_fee < minVariableFee) _fee = minVariableFee;
    if (_fee > maxVariableFee) _fee = maxVariableFee;
    _fee = safeAdd (_fee, fixedFee);
  }

  /**
   * Set flags for given address.
   *
   * @param _address address to set flags for
   * @param _flags flags to set
   */
  function setFlags (address _address, uint256 _flags)
  public delegatable payable {
    require (msg.sender == owner);

    addressFlags [_address] = _flags;
  }

  /**
   * Get flags for given address.
   *
   * @param _address address to get flags for
   * @return flags for given address
   */
  function flags (address _address) public delegatable view returns (uint256) {
    return addressFlags [_address];
  }

  /**
   * Set address of smart contract to delegate execution of delegatable methods
   * to.
   *
   * @param _delegate address of smart contract to delegate execution of
   * delegatable methods to, or zero to not delegate delegatable methods
   * execution.
   */
  function setDelegate (address _delegate) public {
    require (msg.sender == owner);

    if (delegate != _delegate) {
      delegate = _delegate;
      Delegation (delegate);
    }
  }

  /**
   * Get address of this smart contract.
   *
   * @return address of this smart contract
   */
  function thisAddress () internal view returns (address) {
    return this;
  }

  /**
   * Get address of message sender.
   *
   * @return address of this smart contract
   */
  function messageSenderAddress () internal view returns (address) {
    return msg.sender;
  }

  /**
   * Owner of the smart contract.
   */
  address internal owner;

  /**
   * Address where fees are sent to.
   */
  address internal feeCollector;

  /**
   * Number of tokens in circulation.
   */
  uint256 internal tokensCount;

  /**
   * Whether token transfers are currently frozen.
   */
  bool internal frozen;

  /**
   * Mapping from sender's address to the next delegated transfer nonce.
   */
  mapping (address => uint256) internal nonces;

  /**
   * Fixed fee amount in token units.
   */
  uint256 internal fixedFee;

  /**
   * Minimum variable fee in token units.
   */
  uint256 internal minVariableFee;

  /**
   * Maximum variable fee in token units.
   */
  uint256 internal maxVariableFee;

  /**
   * Variable fee numerator.
   */
  uint256 internal variableFeeNumerator;

  /**
   * Maps address to its flags.
   */
  mapping (address => uint256) internal addressFlags;

  /**
   * Address of smart contract to delegate execution of delegatable methods to,
   * or zero to not delegate delegatable methods execution.
   */
  address internal delegate;

  /**
   * Logged when token transfers were frozen.
   */
  event Freeze ();

  /**
   * Logged when token transfers were unfrozen.
   */
  event Unfreeze ();

  /**
   * Logged when fee parameters were changed.
   *
   * @param fixedFee fixed fee in token units
   * @param minVariableFee minimum variable fee in token units
   * @param maxVariableFee maximum variable fee in token units
   * @param variableFeeNumerator variable fee numerator
   */
  event FeeChange (
    uint256 fixedFee,
    uint256 minVariableFee,
    uint256 maxVariableFee,
    uint256 variableFeeNumerator);

  /**
   * Logged when address of smart contract execution of delegatable methods is
   * delegated to was changed.
   *
   * @param delegate new address of smart contract execution of delegatable
   * methods is delegated to or zero if execution of delegatable methods is
   * oot delegated.
   */
  event Delegation (address delegate);
}
