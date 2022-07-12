// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./access/AccessControlManager.sol";
import "./CurrencyOracle.sol";

/// @title Real World Asset Details
/// @notice This contract stores the real world assets for the protocol
/// @dev Extending Ownable and RWAManager for role implementation

contract RWADetails {
    /// @dev All assets are stored with 4 decimal shift unless specified
    uint8 public constant MO_DECIMALS = 4;

    uint16 public constant DAYS_IN_YEAR = 365;
    uint16 public constant DAYS_IN_LEAP_YEAR = 366;

    event RWAUnitCreated(uint256 indexed rWAUnitId);
    event RWAUnitAddedUnitsForTokenId(
        uint256 indexed rWAUnitId,
        uint16 indexed tokenId,
        uint64 units
    );
    event RWAUnitRedeemedUnitsForTokenId(
        uint256 indexed rWAUnitId,
        uint16 indexed tokenId,
        uint64 units
    );
    event RWAUnitDetailsUpdated(
        uint256 indexed rWAUnitId,
        uint64 indexed unitPrice,
        uint32 indexed priceUpdateDate,
        string portfolioDetailsLink
    );
    event RWAUnitSchemeDocumentLinkUpdated(
        uint256 indexed rWAUnitId,
        string schemeDocumentLink
    );
    event CurrencyOracleAddressSet(address indexed currencyOracleAddress);
    event AccessControlManagerSet(address indexed accessControlAddress);
    event SeniorDefaultUpdated(
        uint256 indexed rWAUnitId,
        bool indexed defaultFlag
    );
    event AutoCalcFlagUpdated(
        uint256 indexed rWAUnitId,
        bool indexed autoCalcFlag
    );

    /** @notice This variable (struct RWAUnit) stores details of real world asset (called RWAUnit).
     *  unit price, portfolio details link and price update date are refreshed regularly
     *  The units mapping stores how many real world asset units are held by MoH tokenId.
     *  apy is stored in basis points i.e., 1% = 100 basis points. It is used in calculation of asset value of
     *  the senior unit based on elapsed time.
     *  unitType is a enum {0 = OPEN, 1= JUNIOR, 2= SENIOR} indicating type of RWA unit
     *  nominalUnitPrice holds the value of unitPrice at the time of unit creation. It cannot be updated after creation.
     *  JUNIOR unit:
     *  startDate is mandatory. Rest of the data is same as for a OPEN unit.
     *  SENIOR unit:
     *  defaultFlag is used to indicate asset default.
     *  if autoCalcFlag is set to true then asset value is calculated using apy and time elapsed.
     *  startDate and endDate are mandatory.
     *  compoundingPeriodicity is an enum {0 = none, 1 = monthly, 2 = quarterly, 3 = half-yearly, 4 = yearly }
     */
    /** @dev
     *  uint16 is sufficient for number of MoH tokens since its extremely unlikely to exceed 64k types of MoH tokens
     *  unint64 can hold 1600 trillion units of real world asset with 4 decimal places.
     *  uint32 can only hold 800k units of real world assets with 4 decimal places which might be insufficient
     *  (if each real world asset is $100, that is only $80m)
     */

    struct RWAUnit {
        bool autoCalcFlag;
        bool defaultFlag;
        uint8 unitType;
        uint8 compoundingPeriodicity;
        uint16 tokenId;
        uint16 apy;
        uint32 startDate;
        uint32 endDate;
        uint32 priceUpdateDate;
        uint32 nominalUnitPrice;
        uint64 unitPrice;
        uint64 units;
        bytes32 fiatCurrency;
    }

    /** @notice This variable (struct RWAUnitDetail) stores additional details of real world asset (called RWAUnit).
     *  name is only updatable during creation.
     *  schemeDocumentLink is mostly static.
     *  portfolioDetailsLink is refreshed regularly
     */
    struct RWAUnitDetail {
        string name;
        string schemeDocumentLink;
        string portfolioDetailsLink;
    }

    /// @dev Currency Oracle Address contract associated with RWA unit
    address public currencyOracleAddress;

    /// @dev Implements RWA manager and whitelist access
    address public accessControlManagerAddress;

    /// @dev unique identifier for the rwa unit
    uint256 public rWAUnitId = 1;

    /// @dev used to determine number of days in asset value calculation
    bool leapYear;

    /// @dev mapping between the id and the struct
    mapping(uint256 => RWAUnit) public rWAUnits;

    /// @dev mapping between unit id and additional details
    mapping(uint256 => RWAUnitDetail) public rWAUnitDetails;

    /// @dev mapping of tokenId to rWAUnitIds . Used for calculating asset value for a tokenId.
    mapping(uint256 => uint256[]) public tokenIdToRWAUnitId;

    /// @dev mapping of unit id to compounding periods . Used for calculating asset value for the unit id.
    mapping(uint256 => uint32[]) public rWAUnitIdToCompPeriods;

    /// @dev mapping of unit id to compounding period principals . Amount is stored with 4 decimal precision.
    mapping(uint256 => uint64[]) public rWAUnitIdToCompPeriodPrincipals;

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

    /// @dev Access modifier to restrict access only to RWA manager addresses

    modifier onlyRWAManager() {
        AccessControlManager acm = AccessControlManager(
            accessControlManagerAddress
        );
        require(acm.isRWAManager(msg.sender), "NR");
        _;
    }

    /// @notice Setter for accessControlManagerAddress
    /// @param _accessControlManagerAddress Set accessControlManagerAddress to this address

    function setAccessControlManagerAddress(
        address _accessControlManagerAddress
    ) external onlyOwner {
        accessControlManagerAddress = _accessControlManagerAddress;
        emit AccessControlManagerSet(_accessControlManagerAddress);
    }

    /// @notice Setter for leapYear
    /// @param _leapYear whether current period is in a leap year

    function setLeapYear(bool _leapYear) external onlyRWAManager {
        leapYear = _leapYear;
    }

    /** @notice function createRWAUnit allows creation of a new Real World Asset type (RWA unit)
     *  It takes the name and scheme document as inputs along with initial price and date
     *  Checks on inputs include ensuring name is entered, link is provided for document and initial price is entered
     */
    /// @dev Explain to a developer any extra details
    /// @param _name is the name of the RWA scheme
    /// @param _schemeDocumentLink contains the link for the RWA scheme document
    /// @param _portfolioDetailsLink contains the link for the RWA portfolio details document
    /// @param _fiatCurrency  fiat currency for the unit
    /// @param _nominalUnitPrice price of a single RWA unit
    /// @param _autoCalcFlag specifies whether principal should be auto calculated. Only applicable for senior unit type
    /// @param _units number of units.
    /// @param _dates expects the following dates- [0: start date , 1: end date , 2: last time price was updated]
    /// @param _tokenIdapy expects the following- [0: contains the id of the MoH token to which RWA units are being added, 1: apy ]
    /// @param _unitTypecompoundingPeriodicity expects the following- [0: unitType enum, 1: compoundingPeriodicity enum]
    /// @param _periods expects the period timestamp(seconds) as per the compounding periodicity
    /// @param _compPeriodPrincipals expects the principals for corresponding periods

    function createRWAUnit(
        string memory _name,
        string memory _schemeDocumentLink,
        string memory _portfolioDetailsLink,
        bytes32 _fiatCurrency,
        uint32 _nominalUnitPrice,
        bool _autoCalcFlag,
        uint64 _units,
        uint32[] memory _dates,
        uint16[] memory _tokenIdapy,
        uint8[] memory _unitTypecompoundingPeriodicity,
        uint32[] memory _periods,
        uint64[] memory _compPeriodPrincipals
    ) external onlyRWAManager {
        require(
            (bytes(_name).length > 0) &&
                _tokenIdapy[0] > 0 &&
                _fiatCurrency != "" &&
                _nominalUnitPrice > 0 &&
                _dates.length == 3,
            "BD"
        );
        if (
            _unitTypecompoundingPeriodicity[0] == 1 ||
            _unitTypecompoundingPeriodicity[0] == 2
        ) {
            require(_dates[0] > 0, "WS"); // start date is mandatory
            if (_unitTypecompoundingPeriodicity[0] == 2) {
                require(_dates[1] > 0, "WE"); //end date is mandatory
                if (_autoCalcFlag) {
                    require(
                        _tokenIdapy[1] > 0 &&
                            _periods.length > 0 &&
                            _periods.length == _compPeriodPrincipals.length,
                        "WI"
                    );
                }
            }
        }

        uint256 id = rWAUnitId++;

        rWAUnits[id].fiatCurrency = _fiatCurrency;
        rWAUnits[id].unitPrice = _nominalUnitPrice;
        rWAUnits[id].priceUpdateDate = _dates[2];
        rWAUnits[id].tokenId = _tokenIdapy[0];
        rWAUnits[id].autoCalcFlag = _autoCalcFlag;
        rWAUnits[id].unitType = _unitTypecompoundingPeriodicity[0];
        rWAUnits[id].apy = _tokenIdapy[1];
        rWAUnits[id].startDate = _dates[0];
        rWAUnits[id].endDate = _dates[1];
        rWAUnits[id].nominalUnitPrice = _nominalUnitPrice;
        rWAUnits[id].units = _units;
        rWAUnits[id].compoundingPeriodicity = _unitTypecompoundingPeriodicity[
            1
        ];

        tokenIdToRWAUnitId[_tokenIdapy[0]].push(id);

        rWAUnitDetails[id] = RWAUnitDetail({
            name: _name,
            schemeDocumentLink: _schemeDocumentLink,
            portfolioDetailsLink: _portfolioDetailsLink
        });

        rWAUnitIdToCompPeriods[id] = _periods;
        rWAUnitIdToCompPeriodPrincipals[id] = _compPeriodPrincipals;

        emit RWAUnitCreated(id);
    }

    /** @notice Function allows adding RWA units to a particular RWA unit ID.
     */
    /** @dev Function emits the RWAUnitAddedUnitsForTokenId event which represents RWA id, MoH token id and number of units.
     *      It is read as given number of tokens of RWA id are added to MoH pool represnted by MoH token id
     *  @dev tokenIds stores the MoH token IDs holding units of this RWA.
     *      This mapping is specific to the RWA scheme represented by the struct
     */
    /// @param _id contains the id of the RWA unit being added
    /// @param _units contains the number of RWA units added to the MoH token

    function addRWAUnits(uint256 _id, uint64 _units) external onlyRWAManager {
        RWAUnit storage rWAUnit = rWAUnits[_id];
        rWAUnit.units += _units;
        emit RWAUnitAddedUnitsForTokenId(_id, rWAUnit.tokenId, _units);
    }

    /** @notice Function allows RWA manager to update redemption of RWA units. Redemption of RWA units leads to
     *  an increase in cash / stablecoin balances and reduction in RWA units held.
     *  The cash / stablecoin balances are not handled in this function
     */
    /** @dev Function emits the RWAUnitRedeemedUnitsForTokenId event which represents RWA id, MoH token id and number of units.
     *      It is read as given number of tokens of RWA id are subtracted from the MoH pool represnted by MoH token id
     */
    /// @param _id contains the id of the RWA unit being redeemed
    /// @param _units contains the number of RWA units redeemed from the MoH token

    function redeemRWAUnits(uint256 _id, uint64 _units)
        external
        onlyRWAManager
    {
        RWAUnit storage rWAUnit = rWAUnits[_id];
        require(rWAUnit.units >= _units, "ECA1");
        rWAUnit.units -= _units;
        emit RWAUnitRedeemedUnitsForTokenId(_id, rWAUnit.tokenId, _units);
    }

    /** @notice Function allows RWA Manager to update the RWA scheme documents which provides the parameter of the RWA scheme such as fees,
     *  how the scheme is run etc. This is not expected to be updated frequently
     */
    /// @dev Function emits RWAUnitSchemeDocumentLinkUpdated event which provides id of RWA scheme update and the updated scheme document link
    /// @param _schemeDocumentLink stores the link to the RWA scheme document
    /// @param _id contains the id of the RWA being updated

    function updateRWAUnitSchemeDocumentLink(
        uint256 _id,
        string memory _schemeDocumentLink
    ) external onlyRWAManager {
        require((bytes(_schemeDocumentLink)).length > 0, "ECC2");
        rWAUnitDetails[_id].schemeDocumentLink = _schemeDocumentLink;
        emit RWAUnitSchemeDocumentLinkUpdated(_id, _schemeDocumentLink);
    }

    /** @notice Function allows RWA Manager to update the details of the RWA portfolio.
     *  Changes in the portfolio holdings and / or price of holdings are updated via portfolio details link and
     *  the updated price of RWA is updated in _unitPrice field. This is expected to be updated regulatory
     */
    /// @dev Function emits RWAUnitDetailsUpdated event which provides id of RWA updated, unit price updated and price update date
    /// @param _id Refers to id of the RWA being updated
    /// @param _unitPrice stores the price of a single RWA unit
    /// @param _priceUpdateDate stores the last date on which the RWA unit price was updated by RWA Manager
    /// @param _portfolioDetailsLink stores the link to the file containing details of the RWA portfolio and unit price

    function updateRWAUnitDetails(
        uint256 _id,
        string memory _portfolioDetailsLink,
        uint64 _unitPrice,
        uint32 _priceUpdateDate
    ) external onlyRWAManager {
        require((bytes(_portfolioDetailsLink)).length > 0, "ECC2");

        RWAUnit storage rWAUnit = rWAUnits[_id];
        rWAUnit.unitPrice = _unitPrice;
        rWAUnitDetails[_id].portfolioDetailsLink = _portfolioDetailsLink;
        rWAUnit.priceUpdateDate = _priceUpdateDate;
        emit RWAUnitDetailsUpdated(
            _id,
            _unitPrice,
            _priceUpdateDate,
            _portfolioDetailsLink
        );
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

    /** @notice Function allows RWA Manager to update defaultFlag for a SENIOR unit.
     */
    /// @dev Function emits SeniorDefaultUpdated event which provides id of RWA updated, unit price updated and price update date
    /// @param _id Refers to id of the RWA being updated
    /// @param _defaultFlag boolean value to be set.

    function setSeniorDefault(uint256 _id, bool _defaultFlag)
        external
        onlyRWAManager
    {
        require(rWAUnits[_id].unitType == 2, "BD");
        rWAUnits[_id].defaultFlag = _defaultFlag;
        emit SeniorDefaultUpdated(_id, _defaultFlag);
    }

    /** @notice Function allows RWA Manager to update autoCalcFlag for a SENIOR unit.
     * If value of autoCalcFlag is false then unitPrice and priceUpdateDate are mandatory as asset value should
     * be calculated based on these variables. Only applicable for a senior unitType.
     * If value of autoCalcFlag is true then existing apy, period and princpals should not be empty
     * or input value being passed should have valid data
     */
    /// @dev Function emits AutoCalcFlagUpdated event which provides id of RWA updated and autoCalcFlag value set.
    /// @param _id Refers to id of the RWA being updated
    /// @param _autoCalcFlag Refers to autoCalcFlag of the RWA being updated
    /// @param _unitPrice Refers to unitPrice of the RWA being updated
    /// @param _priceUpdateDate Refers to priceUpdateDate of the RWA being updated
    /// @param _apy Refers to apy of the RWA being updated
    /// @param _periods expects the period timestamp(seconds) as per the compounding periodicity
    /// @param _compPeriodPrincipals expects the principals for corresponding periods

    function updateAutoCalc(
        uint256 _id,
        bool _autoCalcFlag,
        uint32 _unitPrice,
        uint32 _priceUpdateDate,
        uint16 _apy,
        uint32[] memory _periods,
        uint64[] memory _compPeriodPrincipals
    ) external onlyRWAManager {
        require(rWAUnits[_id].unitType == 2, "BD");
        require(
            _autoCalcFlag
                ? ((_apy > 0 &&
                    _periods.length > 0 &&
                    _periods.length == _compPeriodPrincipals.length) ||
                    (rWAUnits[_id].apy > 0 &&
                        rWAUnitIdToCompPeriods[_id].length > 0 &&
                        rWAUnitIdToCompPeriods[_id].length ==
                        rWAUnitIdToCompPeriodPrincipals[_id].length))
                : (_unitPrice > 0 && _priceUpdateDate > 0),
            "WI"
        );

        rWAUnits[_id].autoCalcFlag = _autoCalcFlag;
        if (_autoCalcFlag) {
            if (_apy > 0) {
                rWAUnits[_id].apy = _apy;
                rWAUnitIdToCompPeriods[_id] = _periods;
                rWAUnitIdToCompPeriodPrincipals[_id] = _compPeriodPrincipals;
            }
        } else {
            rWAUnits[_id].unitPrice = _unitPrice;
            rWAUnits[_id].priceUpdateDate = _priceUpdateDate;
        }
        emit AutoCalcFlagUpdated(_id, _autoCalcFlag);
    }

    /** @notice Function returns defaultFlag for the RWA unit id.
     */
    /// @param _id Refers to id of the RWA unit
    /// @return hasDefaulted Value of defaultFlag for the RWA unit

    function defaultFlag(uint256 _id) public view returns (bool hasDefaulted) {
        hasDefaulted = rWAUnits[_id].defaultFlag;
    }

    /** @notice Function returns whether token redemption is allowed for the RWA unit id.
     *  Returns true only if units have been redeemed i.e., set to 0 and defaultFlag is false
     *  In case of non senior units, default return value is true as there are no redemption restrictions.
     */
    /// @param _id Refers to id of the RWA unit
    /// @return redemptionAllowed Indicates whether the RWA unit can be redeemed.

    function isRedemptionAllowed(uint256 _id)
        external
        view
        returns (bool redemptionAllowed)
    {
        if (rWAUnits[_id].unitType != 2) return true;

        redemptionAllowed = rWAUnits[_id].units == 0 && !defaultFlag(_id);
    }

    /** @notice Function returns the value of RWA units held by a given MoH token id.
     *  This is mostly calculated as number of RWA units against the MoH token multiplied by unit price of an RWA token.
     *  In case of a SENIOR unit with autoCalcFlag set to false, compound interest is calculated based on
     *  number of days passed, compounding periodicity and apy.
     *  formula for calculating additional interest is principal*(1 + daysPassed/365*APY) . Since APY is shifted by MO_DECIMALS,
     *  formula changes to  principal*(10**MO_DECIMALS + APY*daysPassed/365)
     *  for additional precison, 1000 is multiplied and divided , so formula changes to
     *  principal*(10**(MO_DECIMALS+3) + APY*daysPassed*1000/365) /1000
     */
    /// @dev Explain to a developer any extra details
    /// @param _tokenId is the MoH token Id for which value of RWA units is being calculated
    /// @param _inCurrency currency in which assetValue is to be returned
    /// @param _date timestamp(seconds) for which value has to be calculated.
    /// @return assetValue real world asset value for the token as per the date in the requested currency. note:  value is shifted by 4 decimals

    function getRWAValueByTokenId(
        uint16 _tokenId,
        bytes32 _inCurrency,
        uint32 _date
    ) external view returns (uint128 assetValue) {
        CurrencyOracle currencyOracle = CurrencyOracle(currencyOracleAddress);

        uint256[] memory tokenUnitIds = tokenIdToRWAUnitId[_tokenId];

        for (uint256 i = 0; i < tokenUnitIds.length; i++) {
            uint256 id = tokenUnitIds[i];
            RWAUnit storage rWAUnit = rWAUnits[id];
            uint128 calculatedAmount = 0;

            if (rWAUnit.unitType == 2 && rWAUnit.autoCalcFlag) {
                // based on apy
                if (_date < rWAUnit.startDate) {
                    //don't do anything if unit has not started yet.
                    continue;
                }

                if (_date > rWAUnit.endDate) {
                    // return final principal if _date is past end date
                    calculatedAmount =
                        rWAUnitIdToCompPeriodPrincipals[id][
                            rWAUnitIdToCompPeriodPrincipals[id].length - 1
                        ] *
                        uint128(10**MO_DECIMALS); //multiplying by apy=1 for decimal correction
                } else {
                    uint128 currentPeriod = 0;
                    //find the principal for the period that has started
                    for (
                        uint256 j = 1;
                        j < rWAUnitIdToCompPeriods[id].length;
                        j++
                    ) {
                        if (_date > rWAUnitIdToCompPeriods[id][j]) {
                            continue;
                        } else {
                            currentPeriod = uint128(j - 1);
                            break;
                        }
                    }

                    calculatedAmount = rWAUnitIdToCompPeriodPrincipals[id][
                        currentPeriod
                    ];

                    uint128 daysPassed = (_date -
                        rWAUnitIdToCompPeriods[id][currentPeriod]) / 1 days;

                    if (daysPassed > 0) {
                        // interest accrued for the time elapsed
                        calculatedAmount =
                            (calculatedAmount *
                                (uint128(10**7) +
                                    (daysPassed * rWAUnit.apy * 1000) /
                                    (
                                        leapYear
                                            ? DAYS_IN_LEAP_YEAR
                                            : DAYS_IN_YEAR
                                    ))) /
                            1000; // multiplying and dividing by 1000 for higher precision.
                    }
                }
            } else {
                // skip units which have no value
                if (rWAUnit.unitPrice == 0 || rWAUnit.units == 0) continue;

                require(rWAUnit.priceUpdateDate == _date, "ECC3");

                calculatedAmount = rWAUnit.unitPrice * rWAUnit.units;
            }
            // convert if necessary and add to assetValue
            if (rWAUnit.fiatCurrency == _inCurrency) {
                assetValue += calculatedAmount;
            } else {
                (uint64 convRate, uint8 decimalsVal) = currencyOracle
                    .getFeedLatestPriceAndDecimals(
                        rWAUnit.fiatCurrency,
                        _inCurrency
                    );
                assetValue += ((calculatedAmount * convRate) /
                    uint128(10**decimalsVal));
            }
        }
        // assetValue is 8 decimal shifted as principal/unitPrice and apy/units are 4 decimal shifted.
        // dividing by 10**4 to return 4 decimal shifted value.
        assetValue = assetValue / uint128(10**MO_DECIMALS);
    }

    /** @notice Function returns RWA units for the token Id
     */
    /// @param _tokenId Refers to token id
    /// @return rWAUnitsByTokenId returns array of RWA Unit IDs associated to tokenId

    function getRWAUnitsForTokenId(uint256 _tokenId)
        external
        view
        returns (uint256[] memory rWAUnitsByTokenId)
    {
        rWAUnitsByTokenId = tokenIdToRWAUnitId[_tokenId];
    }
}
