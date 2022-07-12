// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./StableCoin.sol";
import "./MoToken.sol";
import "./RWADetails.sol";
import "./access/AccessControlManager.sol";

/// @title Token manager for open/senior token
/// @notice This is a token manager which handles all operations related to the token

contract MoTokenManager {
    /// @dev All assets are stored with 4 decimal shift
    uint8 public constant MO_DECIMALS = 4;

    /// @dev RWA Details contract address which stores real world asset details
    address public rWADetails;

    /// @dev Limits the total supply of the token.
    uint256 public tokenSupplyLimit;

    /// @dev Implements RWA manager and whitelist access
    address public accessControlManagerAddress;

    /// @dev Address of the associated MoToken
    address public token;

    /// @dev Holds exponential value for MO token decimals
    uint256 public tokenDecimals;

    /// @dev OraclePriceExchange Address contract associated with the stable coin
    address public currencyOracleAddress;

    /// @dev fiatCurrency associated with tokens
    bytes32 public fiatCurrency = "USD";

    /// @dev platform fee currency associated with tokens
    bytes32 public platformFeeCurrency = "USDC";

    /// @dev Accrued fee amount charged by the platform
    uint256 public accruedPlatformFee;

    /// @dev stableCoin Address contract used for stable coin operations
    address public stableCoinAddress;

    /** @notice This struct stores all the properties associated with the token
     *  id - MoToken id
     *  navDeviationAllowance - Percentage of NAV change allowed without approval flow
     *  nav - NAV for the token
     *  navUnapproved - NAV unapproved value stored for approval flow
     *  stashUpdateDate - Date of last stash update
     *  pipeFiatStash - Fiat amount which is in transmission between the stable coin pipe and the RWA bank account
     *  totalAssetValue - Summation of all the assets owned by the RWA fund that is associated with the MoToken
     */

    struct TokenDetails {
        uint16 id;
        uint16 navDeviationAllowance; // in percent
        uint16 daysInAYear;
        uint32 feeAccrualTimestamp;
        uint32 platformFee; // in basis points
        uint32 stashUpdateDate; // timestamp
        uint32 lastStashUpdateDate;
        uint64 nav; // 4 decimal shifted
        uint64 navUnapproved;
        uint64 pipeFiatStash; // 4 decimal shifted
        uint128 totalAssetValue; // 4 decimal shifted
    }

    TokenDetails public tokenData;

    event Purchase(address indexed user, uint256 indexed tokens);
    event RWADetailsSet(address indexed rwaAddress);
    event FiatCurrencySet(bytes32 indexed currency);
    event FiatCredited(uint64 indexed amount, uint32 indexed date);
    event FiatDebited(uint64 indexed amount, uint32 indexed date);
    event NAVUpdated(uint64 indexed nav, uint32 indexed date);
    event TokenSupplyLimitSet(uint256 indexed tokenSupplyLimit);
    event NAVApprovalRequest(
        uint64 indexed navUnapproved,
        uint32 indexed stashUpdateDate
    );
    event PlatformFeeSet(uint32 indexed platformFee);
    event PlatformFeeCurrencySet(bytes32 indexed currency);
    event FeeTransferred(uint256 indexed fee);
    event AccessControlManagerSet(address indexed accessControlAddress);
    event CurrencyOracleAddressSet(address indexed currencyOracleAddress);

    constructor(address _accessControlManager) {
        accessControlManagerAddress = _accessControlManager;
        emit AccessControlManagerSet(_accessControlManager);
    }

    /// @notice Access modifier to restrict access only to owner

    modifier onlyOwner() {
        AccessControlManager acm = AccessControlManager(
            accessControlManagerAddress
        );
        require(acm.isOwner(msg.sender), "NO");
        _;
    }

    /// @notice Access modifier to restrict access only to whitelisted addresses

    modifier onlyWhitelisted() {
        AccessControlManager acm = AccessControlManager(
            accessControlManagerAddress
        );
        require(acm.isWhiteListed(msg.sender), "NW");
        _;
    }

    /// @notice Access modifier to restrict access only to RWA manager addresses

    modifier onlyRWAManager() {
        AccessControlManager acm = AccessControlManager(
            accessControlManagerAddress
        );
        require(acm.isRWAManager(msg.sender), "NR");
        _;
    }

    /// @notice Access modifier to restrict access only to Admin addresses

    modifier onlyAdmin() {
        AccessControlManager acm = AccessControlManager(
            accessControlManagerAddress
        );
        require(acm.isAdmin(msg.sender), "NA");
        _;
    }

    /// @notice returns the owner address

    function owner() public view returns (address) {
        AccessControlManager acm = AccessControlManager(
            accessControlManagerAddress
        );
        return acm.owner();
    }

    /// @notice Initializes basic properties associated with the token
    /// @param _id MoToken Id
    /// @param _token token address
    /// @param _stableCoin StableCoin contract address
    /// @param _rWADetails RWADetails contract address

    function initialize(
        uint16 _id,
        address _token,
        address _stableCoin,
        uint64 _initNAV,
        address _rWADetails
    ) external {
        require(tokenData.id == 0, "AE");

        tokenData.id = _id;
        token = _token;
        tokenDecimals = 10**MO_DECIMALS;
        stableCoinAddress = _stableCoin;
        rWADetails = _rWADetails;
        tokenData.nav = _initNAV;
        tokenSupplyLimit = 10**10;
        tokenData.navDeviationAllowance = 10;
        tokenData.daysInAYear = 365;
        tokenData.feeAccrualTimestamp = uint32(block.timestamp);
    }

    /// @notice Setter for accessControlManagerAddress
    /// @param _accessControlManagerAddress Set accessControlManagerAddress to this address

    function setAccessControlManagerAddress(
        address _accessControlManagerAddress
    ) external onlyOwner {
        accessControlManagerAddress = _accessControlManagerAddress;
        emit AccessControlManagerSet(_accessControlManagerAddress);
    }

    /// @notice Setter for stableCoin
    /// @param _stableCoinAddress Set stableCoin to this address

    function setStableCoinAddress(address _stableCoinAddress)
        external
        onlyOwner
    {
        stableCoinAddress = _stableCoinAddress;
        // emit AccessControlManagerSet(_accessControlManagerAddress);
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

    /// @notice Setter for platform fee currency
    /// @param _feeCurrency platform fee currency

    function setPlatformFeeCurrency(bytes32 _feeCurrency)
        external
        onlyRWAManager
    {
        platformFeeCurrency = _feeCurrency;
        emit PlatformFeeCurrencySet(platformFeeCurrency);
    }

    /// @notice Setter for platform fee
    /// @param _fee platform fee

    function setFee(uint32 _fee) external onlyOwner {
        require(_fee < 10000, "NA");
        tokenData.platformFee = _fee;
        emit PlatformFeeSet(_fee);
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

    /// @notice Raise request for platform fee transfer to governor
    /// @param amount fee transfer amount

    function sweepFeeToGov(uint256 amount) external onlyAdmin {
        accruedPlatformFee -= amount;
        require(transferFeeToGovernor(amount), "TF");
        emit FeeTransferred(amount);
    }

    /// @notice Calculates the incremental platform fee the given timestamp and
    /// and updates the total accrued fee.
    /// @param _time timestamp for fee accrual

    function accrueFee(uint32 _time) internal {
        uint256 calculatedFee = ((_time - tokenData.feeAccrualTimestamp) *
            tokenData.platformFee *
            getTotalAssetValue()) /
            10**MO_DECIMALS /
            tokenData.daysInAYear /
            1 days;
        tokenData.feeAccrualTimestamp = uint32(_time);
        accruedPlatformFee += calculatedFee;
    }

    /// @notice Returns the token id for the associated token.

    function getId() public view returns (uint16) {
        return tokenData.id;
    }

    /// @notice Sets days in a year to be used in fee calculation.

    function setDaysInAYear(uint16 _days) external onlyRWAManager {
        require(_days == 365 || _days == 366, "INV");
        tokenData.daysInAYear = _days;
    }

    /// @notice This function is called by the purchaser of MoH tokens. The protocol transfers _depositCurrency
    /// from the purchaser and mints and transfers MoH token to the purchaser
    /// @dev tokenData.nav has the NAV (in USD) of the MoH token. The number of MoH tokens to mint = _depositAmount (in USD) / NAV
    /// @param _depositAmount is the amount in stable coin (decimal shifted) that the purchaser wants to pay to buy MoH tokens
    /// @param _depositCurrency is the token that purchaser wants to pay with (eg: USDC, USDT etc)

    function purchase(uint256 _depositAmount, bytes32 _depositCurrency)
        external
        virtual
        onlyWhitelisted
    {
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

        MoToken moToken = MoToken(token);
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

    function getNAV() public view returns (uint64) {
        return tokenData.nav;
    }

    /// @notice The function allows the RWA manager to update the NAV. NAV = (Asset value of AFI _ pipe fiat stash in Fiat +
    /// stablecoin balance) / Total supply of the MoH token.
    /// @dev getTotalAssetValue gets value of all RWA units held by this MoH token plus stablecoin balances
    /// held by this MoH token. tokenData.pipeFiatStash gets the Fiat balances against this MoH token

    function updateNav() external onlyRWAManager {
        uint256 totalSupply = MoToken(token).totalSupply();
        require(totalSupply > 0, "ECT1");
        uint256 totalValue = uint128(getTotalAssetValue()); // 4 decimals shifted

        uint32 navCalculated = uint32(
            (totalValue * tokenDecimals) / totalSupply
        ); //nav should be 4 decimals shifted

        if (
            navCalculated >
            ((tokenData.nav * (100 + tokenData.navDeviationAllowance)) / 100) ||
            navCalculated <
            ((tokenData.nav * (100 - tokenData.navDeviationAllowance)) / 100)
        ) {
            tokenData.navUnapproved = navCalculated;
            emit NAVApprovalRequest(
                tokenData.navUnapproved,
                tokenData.stashUpdateDate
            );
        } else {
            tokenData.nav = navCalculated;
            tokenData.navUnapproved = 0;
            accrueFee(tokenData.stashUpdateDate);
            tokenData.lastStashUpdateDate = tokenData.stashUpdateDate;
            emit NAVUpdated(tokenData.nav, tokenData.stashUpdateDate);
        }
    }

    /// @notice If the change in NAV is more than navDeviationAllowance, it has to be approved by Admin

    function approveNav() external onlyAdmin {
        require(tokenData.navUnapproved > 0, "NA");

        tokenData.nav = tokenData.navUnapproved;
        tokenData.navUnapproved = 0;
        accrueFee(tokenData.stashUpdateDate);
        tokenData.lastStashUpdateDate = tokenData.stashUpdateDate;
        emit NAVUpdated(tokenData.nav, tokenData.stashUpdateDate);
    }

    /// @notice Gets the summation of all the assets owned by the RWA fund that is associated with the MoToken in fiatCurrency
    /// @return totalRWAssetValue Value of all the assets associated with the MoToken

    function getTotalAssetValue()
        internal
        view
        returns (uint256 totalRWAssetValue)
    {
        RWADetails rWADetailsInstance = RWADetails(rWADetails);
        StableCoin sCoin = StableCoin(stableCoinAddress);

        totalRWAssetValue =
            rWADetailsInstance.getRWAValueByTokenId(
                tokenData.id,
                fiatCurrency,
                tokenData.stashUpdateDate
            ) +
            sCoin.totalBalanceInFiat(token, fiatCurrency) +
            tokenData.pipeFiatStash -
            accruedPlatformFee; // 4 decimals shifted
    }

    /// @notice Transfers accrued fees to governor
    /// @param _amount amount in platformFeeCurrency
    /// @return bool Boolean indicating transfer success/failure

    function transferFeeToGovernor(uint256 _amount) internal returns (bool) {
        CurrencyOracle currencyOracle = CurrencyOracle(currencyOracleAddress);
        (uint64 stableToFiatConvRate, uint8 decimalsVal) = currencyOracle
            .getFeedLatestPriceAndDecimals(platformFeeCurrency, fiatCurrency);

        StableCoin sCoin = StableCoin(stableCoinAddress);
        uint8 finalDecVal = decimalsVal +
            sCoin.decimals(platformFeeCurrency) -
            MO_DECIMALS;
        uint256 amount = ((_amount * (10**finalDecVal)) / stableToFiatConvRate);

        require(amount <= sCoin.balanceOf(platformFeeCurrency, token), "NF");

        MoToken moToken = MoToken(token);
        return (
            moToken.transferStableCoins(
                sCoin.contractAddressOf(platformFeeCurrency),
                owner(),
                amount
            )
        );
    }
}
