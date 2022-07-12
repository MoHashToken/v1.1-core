// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./MoJuniorToken.sol";
import "./MoTokenManager.sol";

/// @title Token manager for junior token
/// @notice This is a token manager which handles all operations related to the token

contract MoJuniorTokenManager is MoTokenManager {
    /// @dev Address of the underwriter holding junior token
    address public underwriterAddress;

    /// @dev Holds the corresponding senior RWA Unit ID of the junior token
    uint256 public linkedSrRwaUnitId;

    constructor(address _accessControlManager)
        MoTokenManager(_accessControlManager)
    {}

    /// @notice Sets the address of the underwriter.
    /// @param _underwriter underwriter address

    function setUnderwriter(address _underwriter) external onlyOwner {
        underwriterAddress = _underwriter;
    }

    /// @notice This function is called by the purchaser of MoH tokens. The protocol transfers _depositCurrency
    /// from the purchaser and mints and transfers MoH token to the purchaser.
    /// purchase is restricted to underwriter address only
    /// @dev tokenData.nav has the NAV (in USD) of the MoH token. The number of MoH tokens to mint = _depositAmount (in USD) / NAV
    /// @param _depositAmount is the amount in stable coin (decimal shifted) that the purchaser wants to pay to buy MoH tokens
    /// @param _depositCurrency is the token that purchaser wants to pay with (eg: USDC, USDT etc)

    function purchase(uint256 _depositAmount, bytes32 _depositCurrency)
        external
        override
        onlyWhitelisted
    {
        require(msg.sender == underwriterAddress, "NA");

        CurrencyOracle currencyOracle = CurrencyOracle(currencyOracleAddress);
        (uint64 stableToFiatConvRate, uint8 decimalsVal) = currencyOracle
            .getFeedLatestPriceAndDecimals(_depositCurrency, fiatCurrency);

        StableCoin sCoin = StableCoin(stableCoinAddress);

        int8 decimalCorrection = int8(MO_DECIMALS) +
            int8(MO_DECIMALS) -
            int8(sCoin.decimals(_depositCurrency)) -
            int8(decimalsVal);

        uint256 tokensToMint = _depositAmount * stableToFiatConvRate;
        if (decimalCorrection > -1) {
            tokensToMint = tokensToMint * 10**uint8(decimalCorrection);
        } else {
            decimalCorrection = -decimalCorrection;
            tokensToMint = tokensToMint / 10**uint8(decimalCorrection);
        }
        tokensToMint = tokensToMint / tokenData.nav;

        MoJuniorToken moToken = MoJuniorToken(token);
        require(
            tokenSupplyLimit + moToken.balanceOf(token) >
                moToken.totalSupply() + tokensToMint,
            "LE"
        );
        require(
            sCoin.initiateTransferFrom({
                _token: token,
                _from: msg.sender,
                _amount: _depositAmount,
                _symbol: _depositCurrency
            }),
            "PF"
        );

        moToken.mint(msg.sender, tokensToMint);

        emit Purchase(msg.sender, tokensToMint);
    }

    /// @notice Sets the RWA unit ID corresponding to the junior RWA Unit ID.
    /// @param _unitId Senior RWA Unit ID.

    function setLinkedSrRwaUnitId(uint256 _unitId) external onlyRWAManager {
        linkedSrRwaUnitId = _unitId;
    }
}
