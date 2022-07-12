// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "./interfaces/IERC20Basic.sol";
import "./access/AccessControlManager.sol";

/// @title The ERC20 token contract
/** @dev This contract is an extension of ERC20PresetMinterPauser which has implementations of ERC20, Burnable, Pausable,
 *  Access Control and Context.
 *  In addition to serve as the ERC20 implementation this also serves as a vault which will hold
 *  1. stablecoins transferred from the users during token purchase and
 *  2. tokens themselves which are transferred from the users while requesting for redemption
 *  3. restrict transfers to only whitelisted addresses
 */

contract MoToken is ERC20PresetMinterPauser {

    /// @dev Address of contract which manages whitelisted addresses
    address public accessControlManagerAddress;

    /// @notice Constructor which only serves as passthrough for _tokenName and _tokenSymbol

    constructor(string memory _tokenName, string memory _tokenSymbol)
        ERC20PresetMinterPauser(_tokenName, _tokenSymbol)
    {
    }

    /// @notice Burns tokens from the given address
    /// @param _tokens The amount of tokens to burn
    /// @param _address The address which holds the tokens

    function burn(uint256 _tokens, address _address) external {
        require(hasRole(MINTER_ROLE, msg.sender), "NW");
        require(balanceOf(_address) >= _tokens, "NT");
        _burn(_address, _tokens);
    }

    /// @notice Transfers MoTokens from self to an external address
    /// @param _address External address to transfer tokens to
    /// @param _tokens The amount of tokens to transfer
    /// @return bool Boolean indicating whether the transfer was success/failure

    function transferTokens(address _address, uint256 _tokens)
        external
        returns (bool)
    {
        require(hasRole(MINTER_ROLE, msg.sender), "NW");
        IERC20Basic ier = IERC20Basic(address(this));
        return (ier.transfer(_address, _tokens));
    }

    /// @notice Transfers stablecoins from self to an external address
    /// @param _contractAddress Stablecoin contract address on chain
    /// @param _address External address to transfer stablecoins to
    /// @param _amount The amount of stablecoins to transfer
    /// @return bool Boolean indicating whether the transfer was success/failure

    function transferStableCoins(
        address _contractAddress,
        address _address,
        uint256 _amount
    ) external returns (bool) {
        require(hasRole(MINTER_ROLE, msg.sender), "NW");
        IERC20Basic ier = IERC20Basic(_contractAddress);
        return (ier.transfer(_address, _amount));
    }

    /// @notice Transfers MoTokens from an external address to self
    /// @param _address External address to transfer tokens from
    /// @param _tokens The amount of tokens to transfer
    /// @return bool Boolean indicating whether the transfer was success/failure

    function receiveTokens(address _address, uint256 _tokens)
        external
        returns (bool)
    {
        IERC20Basic ier = IERC20Basic(address(this));
        return (ier.transferFrom(_address, address(this), _tokens));
    }

    /// @notice Transfers stablecoins from an external address to self
    /// @param _contractAddress Stablecoin contract address on chain
    /// @param _address External address to transfer stablecoins from
    /// @param _amount The amount of stablecoins to transfer
    /// @return bool Boolean indicating whether the transfer was success/failure

    function receiveStableCoins(
        address _contractAddress,
        address _address,
        uint256 _amount
    ) external returns (bool) {
        IERC20Basic ier = IERC20Basic(_contractAddress);
        return (ier.transferFrom(_address, address(this), _amount));
    }

    /// @notice Checks if the given address is whitelisted
    /// @param _account External address to check

    function _onlywhitelisted(address _account) internal view {
        AccessControlManager acm = AccessControlManager(accessControlManagerAddress);
        require(acm.isWhiteListed(_account), "NW");
    }

    /// @notice Overrides transferFrom() function to add whitelist check
    /// @param _from Extermal address from which tokens are transferred
    /// @param _to External address to which tokesn are transferred
    /// @param _amount Amount of tokens to be transferred
    /// @return bool Boolean indicating whether the transfer was success/failure

    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        _onlywhitelisted(_to);
        return super.transferFrom(_from, _to, _amount);
    }

    /// @notice Overrides transfer() function to add whitelist check
    /// @param _to External address to which tokesn are transferred
    /// @param _amount Amount of tokens to be transferred
    /// @return bool Boolean indicating whether the transfer was success/failure

    function transfer(address _to, uint256 _amount) public override returns (bool) {
        _onlywhitelisted(_to);
        return super.transfer(_to, _amount);
    }

    /// @notice Overrides mint() function to add whitelist check
    /// @param _to External address to which tokesn are minted
    /// @param _amount Amount of tokens to be minted

    function mint(address _to, uint256 _amount) public override {
        _onlywhitelisted(_to);
        super.mint(_to, _amount);
    }

    /// @notice Setter for accessControlManagerAddress
    /// @param _address Set accessControlManagerAddress to this address

    function setAccessControlManagerAddress(address _address) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "NW");
        accessControlManagerAddress = _address;
    }

}
