// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./StableCoin.sol";
import "./MoToken.sol";
import "./RWADetails.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./access/AccessControlManager.sol";

/// @title Token manager
/// @notice This is a token manager which handles all operations related to the token
/// @dev Extending Ownable and RWAManager for role implementation and StableCoin for stable coin related functionalities

contract MoTokenManager is StableCoin, Ownable {
    /// @dev RWA Details contract address which stores real world asset details
    address public rWADetails;

    /// @dev Limits the total supply of the token.
    uint256 public tokenSupplyLimit;

    /// @dev Implements RWA manager and whitelist access
    address public accessControlManagerAddress;

    /** @notice This struct stores all the properties associated with the token
     *  id - MoToken id
     *  navDeviationAllowance - Percentage of NAV change allowed without approval flow
     *  nav - NAV for the token
     *  navUnapproved - NAV unapproved value stored for approval flow
     *  stashUpdateDate - Date of last stash update
     *  pipeFiatStash - Fiat amount which is in transmission between the stable coin pipe and the RWA bank account
     *  totalAssetValue - Summation of all the assets owned by the RWA fund that is associated with the MoToken
     */

    struct tokenDetails {
        uint16 id;
        uint16 navDeviationAllowance; // in percent
        uint32 nav; // 6 decimal shifted
        uint32 navUnapproved;
        uint32 stashUpdateDate;
        uint64 pipeFiatStash; // 6 decimal shifted
        uint128 totalAssetValue; // 6 decimal shifted
    }

    tokenDetails public tokenData = tokenDetails(0, 0, 0, 0, 0, 0, 0);

    event Purchase(address indexed user, uint256 indexed tokens);
    event RWADetailsSet(address indexed rwaAddress);
    event FiatCurrencySet(bytes32 indexed currency);
    event FiatCredited(uint64 indexed amount, uint32 indexed date);
    event FiatDebited(uint64 indexed amount, uint32 indexed date);
    event NAVUpdated(uint32 indexed nav, uint32 indexed date);
    event TokenSupplyLimitSet(uint256 indexed tokenSupplyLimit);
    event NAVApprovalRequest(uint32 indexed navUnapproved, uint32 indexed stashUpdateDate);

    /// @notice Access modifier to restrict access only to whitelisted addresses

    modifier onlyWhitelisted() {
        AccessControlManager acm = AccessControlManager(accessControlManagerAddress);
        require(acm.isWhiteListed(msg.sender), "NW");
        _;
    }

    /// @notice Access modifier to restrict access only to RWA manager addresses

    modifier onlyRWAManager() {
        AccessControlManager acm = AccessControlManager(accessControlManagerAddress);
        require(acm.isRWAManager(msg.sender), "NR");
        _;
    }

    /// @notice Access modifier to restrict access only to Admin addresses

    modifier onlyAdmin() {
        AccessControlManager acm = AccessControlManager(accessControlManagerAddress);
        require(acm.isAdmin(msg.sender), "NA");
        _;
    }

    /// @notice Initializes basic properties associated with the token
    /// @param _id MoToken Id
    /// @param _token token address
    /// @param _rWADetails RWADeteails contract address

    function initialize(
        uint16 _id,
        address _token,
        address _rWADetails
    ) external {
        require(tokenData.id == 0, "AE");

        tokenData.id = _id;
        token = _token;
        rWADetails = _rWADetails;
        tokenData.nav = 10**6;
        tokenSupplyLimit = 10**24;
        tokenData.navDeviationAllowance = 10;
    }

    /// @notice Setter for accessControlManagerAddress
    /// @param _accessControlManagerAddress Set accessControlManagerAddress to this address

    function setAccessControlManagerAddress(address _accessControlManagerAddress) external onlyOwner {
        accessControlManagerAddress = _accessControlManagerAddress;
    }

    /// @notice Setter for RWADetails contract associated with the MoToken
    /// @param _rWADetails Address of contract storing RWADetails

    function setRWADetailsAddress(address _rWADetails) external onlyOwner {
        rWADetails = _rWADetails;
        emit RWADetailsSet(rWADetails);
    }

    /// @notice Allows setting currencyOracleAddress
    /// @param _currencyOracleAddress address of the currency oracle

    function setCurrencyOracleAddress(address _currencyOracleAddress)
        external
        onlyOwner
    {
        currencyOracleAddress = _currencyOracleAddress;
        emit CurrencyOracleAddressSet(currencyOracleAddress);
    }

    /// @notice Allows setting fiatCurrecy associated with tokens
    /// @param _fiatCurrency fiatCurrency

    function setFiatCurrency(bytes32 _fiatCurrency) external onlyOwner {
        fiatCurrency = _fiatCurrency;
        emit FiatCurrencySet(fiatCurrency);
    }

    /// @notice Allows setting tokenSupplyLimit associated with tokens
    /// @param _tokenSupplyLimit limit to be set for the token supply

    function setTokenSupplyLimit(uint256 _tokenSupplyLimit)
        external
        onlyRWAManager
    {
        tokenSupplyLimit = _tokenSupplyLimit;
        emit TokenSupplyLimitSet(tokenSupplyLimit);
    }

    /// @notice Allows setting NAV deviation allowance by Owner
    /// @param _value Allowed deviation limit (Eg: 10 for 10% deviation)

    function setNavDeviationAllowance(uint16 _value) external onlyOwner {
    	tokenData.navDeviationAllowance = _value;
    }

    /// @notice This function is called by the purchaser of MoH tokens. The protocol transfers _depositCurrency
    /// from the purchaser and mints and transfers MoH token to the purchaser
    /// @dev tokenData.nav has the NAV (in USD) of the MoH token. The number of MoH tokens to mint = _depositAmount (in USD) / NAV
    /// @param _depositAmount is the amount in USD (shifted by 6 decimal places) that the purchaser wants to send to buy MoH tokens
    /// @param _depositCurrency is the token that purchaser wants to send the amount in (ex: USDC, USDT etc)

    function purchase(uint256 _depositAmount, bytes32 _depositCurrency)
        external onlyWhitelisted
    {
        CurrencyOracle currencyOracle = CurrencyOracle(currencyOracleAddress);
        (uint64 stableToFiatConvRate, uint8 decimalsVal) = currencyOracle
            .getFeedLatestPriceAndDecimals(_depositCurrency, fiatCurrency);

        uint256 tokensToMint = (_depositAmount *
            stableToFiatConvRate *
            10**(6 + getDecimalsDiff(_depositCurrency) - decimalsVal)) /
            tokenData.nav; // Decimal correction:: nav: 6 decimal shifted. amount: mo token decimals - stable currency decimals.

        MoToken moToken = MoToken(token);
        require(
            tokenSupplyLimit + moToken.balanceOf(token) >
                moToken.totalSupply() + tokensToMint,
            "LE"
        );
        require(
            initiateTransferFrom({
                _from: msg.sender,
                _amount: _depositAmount,
                _symbol: _depositCurrency
            }),
            "PF"
        );

        moToken.mint(msg.sender, tokensToMint);

        emit Purchase(msg.sender, moToken.balanceOf(msg.sender));
    }

    /// @notice The function allows RWA manger to provide the increase in pipe fiat balances against the MoH token
    /// @param _amount the amount by which RWA manager is increasing the pipeFiatStash of the MoH token
    /// @param _date RWA manager is crediting pipe fiat for this date

    function creditPipeFiat(uint64 _amount, uint32 _date)
        external
        onlyRWAManager
    {
        tokenData.pipeFiatStash += _amount;
        tokenData.stashUpdateDate = _date;
        emit FiatCredited(tokenData.pipeFiatStash, _date);
    }

    /// @notice The function allows RWA manger to decrease pipe fiat balances against the MoH token
    /// @param _amount the amount by which RWA manager is decreasing the pipeFiatStash of the MoH token
    /// @param _date RWA manager is debiting pipe fiat for this date

    function debitPipeFiat(uint64 _amount, uint32 _date)
        external
        onlyRWAManager
    {
        tokenData.pipeFiatStash -= _amount;
        tokenData.stashUpdateDate = _date;
        emit FiatDebited(tokenData.pipeFiatStash, _date);
    }

    /// @notice Provides the NAV of the MoH token
    /// @return tokenData.nav NAV of the MoH token

    function getNAV() external view returns (uint32) {
        return tokenData.nav;
    }

    /// @notice The function allows the RWA manager to update the NAV. NAV = (Asset value of AFI _ pipe fiat stash in Fiat +
    /// stablecoin balance) / Total supply of the MoH token.
    /// @dev getTotalRWAssetValue gets value of all RWA units held by this MoH token. totalBalanceInFiat() gets stablecoin balances
    /// held by this MoH token. tokenData.pipeFiatStash gets the Fiat balances against this MoH token

    function updateNav() external  onlyRWAManager {
        uint256 totalSupply = MoToken(token).totalSupply();
        require(totalSupply > 0, "ECT1");
        tokenData.totalAssetValue = getTotalRWAssetValue(); // 6 decimals shifted

        uint256 totalValue = totalBalanceInFiat() +
            tokenData.pipeFiatStash +
            tokenData.totalAssetValue; // 6 decimals shifted

        uint32 navCalculated = uint32(
            (totalValue * (10**(MoToken(token).decimals()))) / totalSupply
        ); //nav should be 6 decimals shifted

        if(navCalculated > (tokenData.nav * (100 + tokenData.navDeviationAllowance) / 100) || 
        	navCalculated < (tokenData.nav * (100 - tokenData.navDeviationAllowance) / 100)) {
        	tokenData.navUnapproved = navCalculated;
        	emit NAVApprovalRequest(tokenData.navUnapproved, tokenData.stashUpdateDate);
        } else {
        	tokenData.nav = navCalculated;
        	tokenData.navUnapproved = 0;
        	emit NAVUpdated(tokenData.nav, tokenData.stashUpdateDate);
        }
    }

    /// @notice If the change in NAV is more than navDeviationAllowance, it has to be approved by Admin

    function approveNav() external onlyAdmin {
    	require(tokenData.navUnapproved > 0, "NA");
    	tokenData.nav = tokenData.navUnapproved;
        emit NAVUpdated(tokenData.nav, tokenData.stashUpdateDate);
    }

    /// @notice Gets the summation of all the assets owned by the RWA fund that is associated with the MoToken in fiatCurrency
    /// @return totalRWAssetValue Value of all the assets associated with the MoToken

    function getTotalRWAssetValue()
        internal
        view
        returns (uint128 totalRWAssetValue)
    {
        RWADetails rWADetailsInstance = RWADetails(rWADetails);
        totalRWAssetValue = rWADetailsInstance.getRWAValueByTokenId(
            tokenData.id,
            fiatCurrency,
            tokenData.stashUpdateDate
        ); // 6 decimals shifted in fiatCurrency
    }

    /// @notice This function allows the RWA Manager to transfer stablecoins held by the MoH token to a preset address
    /// from where it can be invested in Real world assets
    /// @param _currency stablecoin to transfer
    /// @param _amount number of stablecoins to transfer
    /// @return bool a boolean value indicating if the transfer was successful or not

    function transferFundsToPipe(bytes32 _currency, uint256 _amount)
        external
        onlyRWAManager
        returns (bool)
    {
        return (_transferFundsToPipe(_currency, _amount));
    }

    /// @notice This function allows the protocol to accept a new stablecoin for purchases of MoH token. It also sets the address
    /// to which this stablecoin balances are sent in order to deploy in real world assets
    /// @param _symbol symbol of stablecoin to add
    /// @param _contractAddress address of stablecoin contract to add
    /// @param _pipeAddress Address to which stablecoin balances are to be transferred in order to deploy in real world assets

    function addStableCoin(
        bytes32 _symbol,
        address _contractAddress,
        address _pipeAddress
    ) external onlyOwner {
        _addStableCoin(_symbol, _contractAddress, _pipeAddress);
    }

    /// @notice This function allows the protocol to delete a stablecoin for purchases of MoH token
    /// @param _symbol symbol of stablecoin to be deleted

    function deleteStableCoin(bytes32 _symbol) external onlyOwner {
        _deleteStableCoin(_symbol);
    }
}
