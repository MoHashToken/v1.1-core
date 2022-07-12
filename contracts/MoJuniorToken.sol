// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;
import "./MoToken.sol";

contract MoJuniorToken is MoToken {
    /// @notice Constructor which only serves as passthrough for _tokenName and _tokenSymbol

    constructor(string memory _tokenName, string memory _tokenSymbol)
        MoToken(_tokenName, _tokenSymbol)
    {}

    /// @notice Overrides transferFrom() function to restrict tranfer tokes b/w external addresses
    /// @param _from Extermal address from which tokens are transferred
    /// @param _to External address to which tokesn are transferred
    /// @param _amount Amount of tokens to be transferred
    /// @return bool Boolean indicating whether the transfer was success/failure

    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) public override returns (bool) {
        require(((_from == address(this)) || (_to == address(this))), "NA");
        return super.transferFrom(_from, _to, _amount);
    }

    /// @notice Overrides transfer() function to restrict tranfer tokes to external address
    /// @param _to External address to which tokesn are transferred
    /// @param _amount Amount of tokens to be transferred
    /// @return bool Boolean indicating whether the transfer was success/failure

    function transfer(address _to, uint256 _amount)
        public
        override
        returns (bool)
    {
        require(
            ((msg.sender == address(this)) || (_to == address(this))),
            "NA"
        );
        return super.transfer(_to, _amount);
    }
}
