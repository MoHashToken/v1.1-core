// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./access/AccessControlManager.sol";
import "./CurrencyOracle.sol";

/// @title Real World Asset Details
/// @notice This contract stores the real world assets for the protocol
/// @dev Extending Ownable and RWAManager for role implementation

contract RWADetails is Ownable {
    event RWAUnitCreated(uint256 indexed rWAUnitId, string name);
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
        uint32 indexed unitPrice,
        uint32 indexed priceUpdateDate,
        string portfolioDetailsLink
    );
    event RWAUnitSchemeDocumentLinkUpdated(
        uint256 indexed rWAUnitId,
        string schemeDocumentLink
    );
    event CurrencyOracleAddressSet(address indexed currencyOracleAddress);

    /** @notice This variable (struct RWAUnit) stores details of real world asset (called RWAUnit). unit price,
     *  portfolio details link and price update date are refreshed regularly
     *  Name, scheme document are more static. The number of units assigned to each MoH token are stored in the 2 mappings
     *  The tokenIdAssociated mapping maps whether a particular MoH token has any of the real world asset units.
     *  The tokenIdToUnits mapping stores how many real world asset units are held by each MoH token
     */
    /** @dev uint is used in mapping since token IDs for MoH token and number of units of real world asset cannot be negative
     *  uint16 is sufficient for number of MoH tokens since its extremely unlikely to exceed 64k types of MoH tokens
     *  unint64 can hold 1600 trillion units of real world asset with 4 decimal places.
     *  uint32 can only hold 800k units of real world assets with 4 decimal places which might be insufficient
     *  (if each real world asset is $100, that is only $80m)
     */

    struct RWAUnit {
        uint32 unitPrice; // stores in paise, so 2 decimals
        uint32 priceUpdateDate;
        bytes32 fiatCurrency;
        string name;
        string schemeDocumentLink;
        string portfolioDetailsLink;
        uint16[] tokenIds;
        mapping(uint16 => bool) tokenIdAssociated;
        mapping(uint16 => uint64) tokenIdToUnits; //units can hold 4 decimal places
    }

    /// @dev unique identifier for the rwa unit
    uint256 public rWAUnitId;

    /// @dev mapping between the id and the struct
    mapping(uint256 => RWAUnit) public rWAUnits;

    /// @dev Currency Oracle Address contract associated with RWA unit
    address public currencyOracleAddress;

    /// @dev Implements RWA manager and whitelist access
    address public accessControlManagerAddress;

    /// @dev Access modifier to restrict access only to RWA manager addresses

    modifier onlyRWAManager() {
        AccessControlManager acm = AccessControlManager(accessControlManagerAddress);
        require(acm.isRWAManager(msg.sender), "NR" );
        _;
    }

    /// @notice Setter for accessControlManagerAddress
    /// @param _accessControlManagerAddress Set accessControlManagerAddress to this address

    function setAccessControlManagerAddress(address _accessControlManagerAddress) external onlyOwner {
        accessControlManagerAddress = _accessControlManagerAddress;
    }

    /** @notice function createRWAUnit allows creation of a new Real World Asset type (RWA unit)
     *  It takes the name and scheme document as inputs along with initial price and date
     *  Checks on inputs include ensuring name is entered, link is provided for document and initial price is entered
     */
    /// @dev Explain to a developer any extra details
    /// @param _name is the name of the RWA scheme
    /// @param _schemeDocumentLink contains  the link for the RWA scheme document
    /// @param _unitPrice stores the price of a single RWA unit
    /// @param _priceUpdateDate stores the last date on which the RWA unit price was updated by RWA Manager
    /// @return id - Function returns the RWA unit id which is a unique identified for an RWA scheme

    function createRWAUnit(
        string memory _name,
        string memory _schemeDocumentLink,
        bytes32 _fiatCurrency,
        uint32 _unitPrice,
        uint32 _priceUpdateDate
    ) external onlyRWAManager returns (uint256 id) {
        require(
            (bytes(_name).length) > 0 &&
                (bytes(_schemeDocumentLink)).length > 0 &&
                _unitPrice > 0 &&
                _fiatCurrency != "",
            "BD"
        );

        id = rWAUnitId++;

        RWAUnit storage newRWAUnit = rWAUnits[id];
        newRWAUnit.name = _name;
        newRWAUnit.schemeDocumentLink = _schemeDocumentLink;
        newRWAUnit.fiatCurrency = _fiatCurrency;
        newRWAUnit.unitPrice = _unitPrice;
        newRWAUnit.priceUpdateDate = _priceUpdateDate;

        emit RWAUnitCreated(id, _name);
    }

    /** @notice Function allows adding RWA units to a particular MoH token. As input it requires, RWA id to add,
     *  MoH token id to which is needs to be added and number of RWA units to add. The number of units added must be greater than 0
     *  If a particular token ID does not have RWA units currently, the tokenIdAssociated mapping is updated to reflect new status
     *  and arry of tokenIds holding this RWA unit is also updated
     */
    /** @dev Function emits the RWAUnitAddedUnitsForTokenId event which represents RWA id, MoH token id and number of units.
     *      It is read as given number of tokens of RWA id are added to MoH pool represnted by MoH token id
     *  @dev tokenIdtoUnits maps MoH token ID to number of RWA units held by that MoH token.
     *      This mapping is specific to the RWA scheme represented by the struct
     *  @dev tokenIds stores the MoH token IDs holding units of this RWA.
     *      This mapping is specific to the RWA scheme represented by the struct
     *  @dev tokenIdAssociated stores a true / false value.
     *      A true value represents that the MoH token represented by the token ID holds units of this RWA
     */
    /// @param _id contains the id of the RWA unit being added
    /// @param _tokenId contains the id of the MoH token to which RWA units are being added
    /// @param _units contains the number of RWA units added to the MoH token

    function addRWAUnitsForTokenId(
        uint256 _id,
        uint16 _tokenId,
        uint64 _units
    ) external onlyRWAManager {
        require(_units > 0, "ECC1");
        RWAUnit storage rWAUnit = rWAUnits[_id];
        rWAUnit.tokenIdToUnits[_tokenId] += _units;
        if (!rWAUnit.tokenIdAssociated[_tokenId]) {
            rWAUnit.tokenIdAssociated[_tokenId] = true;
            rWAUnit.tokenIds.push(_tokenId);
        }
        emit RWAUnitAddedUnitsForTokenId(_id, _tokenId, _units);
    }

    /** @notice Function allows RWA manager to update redemption of RWA units into the database. Redemption of RWA units leads to
     *  an increase in cash / stablecoin balances and reduction in RWA units held.
     *  The cash / stablecoin balances are not handled in thsi function
     */
    /** @dev Function emits the RWAUnitRedeemedUnitsForTokenId event which represents RWA id, MoH token id and number of units.
     *      It is read as given number of tokens of RWA id are subtracted from the MoH pool represnted by MoH token id
     *  @dev tokenIdtoUnits maps MoH token ID to number of RWA units held by that MoH token.
     *      This mapping is specific to the RWA scheme represented by the struct
     */
    /// @param _id contains the id of the RWA unit being redeemed
    /// @param _tokenId contains the id of the MoH token whose holdings of the RWA unit are being redeemed
    /// @param _units contains the number of RWA units redeemed from the MoH token

    function redeemRWAUnitsForTokenId(
        uint256 _id,
        uint16 _tokenId,
        uint64 _units
    ) external onlyRWAManager {
        require(_units > 0, "ECC1");
        RWAUnit storage rWAUnit = rWAUnits[_id];
        require(rWAUnit.tokenIdToUnits[_tokenId] >= _units, "ECA1");

        rWAUnit.tokenIdToUnits[_tokenId] -= _units;
        emit RWAUnitRedeemedUnitsForTokenId(_id, _tokenId, _units);
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
        RWAUnit storage rWAUnit = rWAUnits[_id];
        rWAUnit.schemeDocumentLink = _schemeDocumentLink;
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
        uint32 _unitPrice,
        uint32 _priceUpdateDate
    ) external onlyRWAManager {
        require(_unitPrice > 0, "ECC1");
        require((bytes(_portfolioDetailsLink)).length > 0, "ECC2");

        RWAUnit storage rWAUnit = rWAUnits[_id];
        rWAUnit.unitPrice = _unitPrice;
        rWAUnit.portfolioDetailsLink = _portfolioDetailsLink;
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

    /** @notice Function returns the value of RWA units held by a given MoH token id. This is calculated as number of RWA units
     *  against the MoH token multiplied by unit price of an RWA token.
     */
    /// @dev Explain to a developer any extra details
    /// @param _tokenId is the MoH token Id for which value of RWA units is being calculated
    /// @param _inCurrency currency in which assetValue is to be returned
    /// @return assetValue real world asset value for the token in the requested currency, shifted by 6 decimals

    function getRWAValueByTokenId(
        uint16 _tokenId,
        bytes32 _inCurrency,
        uint32 _date
    ) external view returns (uint128 assetValue) {
        CurrencyOracle currencyOracle = CurrencyOracle(currencyOracleAddress);
        for (uint256 i = 0; i < rWAUnitId; i++) {
            RWAUnit storage rWAUnit = rWAUnits[i];
            require(rWAUnit.priceUpdateDate == _date, "ECC3");
            (uint64 convRate, uint8 decimalsVal) = currencyOracle
                .getFeedLatestPriceAndDecimals(
                    rWAUnit.fiatCurrency,
                    _inCurrency
                );
            assetValue +=
                (rWAUnit.unitPrice *
                    convRate *
                    rWAUnit.tokenIdToUnits[_tokenId]) /
                uint128(10**decimalsVal);
        }
    }

    /** @notice Function provides all details retated a given RWA scheme. These include docuements related to the scheme, number of RWA units
     *  held by each MoH token id, price of RWA unit and document containing portfolio details of the RWA scheme
     */
    /// @dev rWAUnits is an array of RWAUnit structs. Each struct contains details of a particular RWA scheme and which MoH tokens have units of this RWA
    /// @dev rWAUnit is the struct for the RWA represented by ID _id (input to the function)
    /// @param _id rerpresnts the RWA scheme whose details are being provided by the function
    /** @return name is the name of the RWA scheme
     *  @return schemeDocumentLink stores the link to the RWA scheme document
     *  @return portfolioDetailsLink stores the link to the file containing details of the RWA portfolio and unit price
     *  @return fiatCurrency Fiat currency used for the RWA unit
     *  @return unitPrice stores the price of a single RWA unit
     *  @return priceUpdateDate stores the last date on which the RWA unit price was updated by RWA Manager
     *  @return tokenIds is an array storing the MoH token IDs holding units of this RWA.
     *          This array is specific to the RWA scheme represented by the struct
     *  @return tokenUnits is an array storing the number of RWA units held by each MoH token represented in tokenIds array.
     *          This arrary is specific to the RWA scheme represented by the struct
     *  @return tokenIdAssociated is an array containing true / false vaules.
     *          If the MoH tokens represented in the tokenIds array contain units of this RWA, a true value is held, else a false value is held
     */

    function getRWAUnitDetails(uint256 _id)
        external
        view
        returns (
            string memory name,
            string memory schemeDocumentLink,
            string memory portfolioDetailsLink,
            bytes32 fiatCurrency,
            uint32 unitPrice,
            uint32 priceUpdateDate,
            uint16[] memory tokenIds,
            uint64[] memory tokenUnits,
            bool[] memory tokenIdAssociated
        )
    {
        RWAUnit storage rWAUnit = rWAUnits[_id];
        name = rWAUnit.name;
        fiatCurrency = rWAUnit.fiatCurrency;
        unitPrice = rWAUnit.unitPrice;
        priceUpdateDate = rWAUnit.priceUpdateDate;
        schemeDocumentLink = rWAUnit.schemeDocumentLink;
        portfolioDetailsLink = rWAUnit.portfolioDetailsLink;
        tokenIds = rWAUnit.tokenIds;
        tokenUnits = new uint64[](tokenIds.length);
        tokenIdAssociated = new bool[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenUnits[i] = rWAUnit.tokenIdToUnits[tokenIds[i]];
            tokenIdAssociated[i] = rWAUnit.tokenIdAssociated[tokenIds[i]];
        }
    }
}
