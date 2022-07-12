// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;
import "./MoTokenManager.sol";
import "./MoTokenManagerFactory.sol";
import "./StableCoin.sol";
import "./CurrencyOracle.sol";
import "./access/AccessControlManager.sol";
import "./interfaces/IERC20Basic.sol";

/// @title Token Trade Listing Contract
/// @notice This contract handles P2P trade listing and purchase of tokens

contract MoTokenTrader {
    /// @dev All assets are stored with 4 decimal shift
    uint8 public constant MO_DECIMALS = 4;

    /// @dev Token manager factory address
    address public tokenManagerFactoryAddress;

    /// @notice This struct holds the listing details raised by a user

    struct TokenListing {
        address seller;
        bytes32 tokenSymbol;
        uint256 listedTokens;
        uint256 listedTokensPending;
        int256 listedPrice;
    }

    /// @dev An array of all the listing instances created till date
    TokenListing[] public allListings;

    /// @dev Mapping stores the total tokens listed by the users/addresses for a symbol
    mapping(bytes32 => mapping(address => uint256)) public totalTokensListedOf;

    /// @dev Index of the listings which are yet to be closed
    uint256 public listingHead;

    /// @dev Index beyond the last listing
    uint256 public listingTail;

    /// @dev Currency Oracle Address contract associated with the batch processor
    address public currencyOracleAddress;

    /// @dev Implements RWA manager and whitelist access
    address public accessControlManagerAddress;

    /// @dev stableCoin Address contract used for stable coin operations
    address public stableCoinAddress;

    event CurrencyOracleAddressSet(address indexed currencyOracleAddress);
    event AccessControlManagerSet(address indexed accessControlAddress);
    event CreatedListing(
        address indexed sellerAddress,
        bytes32 indexed tokenSymbol,
        uint256 indexed tokens
    );
    event CancelledListing(
        address indexed sellerAddress,
        uint256 indexed listingId
    );
    event EditedListing(
        address indexed sellerAddress,
        uint256 indexed listingId,
        uint256 indexed tokens
    );
    event PurchasedFromListing(
        uint256 indexed listingId,
        uint256 indexed tokens,
        address indexed buyerAddress
    );

    constructor(
        address _factory,
        address _stableCoin,
        address _accessControlManager
    ) {
        tokenManagerFactoryAddress = _factory;
        stableCoinAddress = _stableCoin;
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

    /// @notice Access modifier to restrict access only to RWA manager addresses

    modifier onlyRWAManager() {
        AccessControlManager acm = AccessControlManager(
            accessControlManagerAddress
        );
        require(acm.isRWAManager(msg.sender), "NR");
        _;
    }

    /// @notice Access modifier to restrict access only to whitelisted addresses

    modifier onlywhitelisted() {
        AccessControlManager acm = AccessControlManager(
            accessControlManagerAddress
        );
        require(acm.isWhiteListed(msg.sender), "NW");
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

    /// @notice Allows setting currencyOracleAddress
    /// @param _currencyOracleAddress address of the currency oracle

    function setCurrencyOracleAddress(address _currencyOracleAddress)
        external
        onlyOwner
    {
        currencyOracleAddress = _currencyOracleAddress;
        emit CurrencyOracleAddressSet(currencyOracleAddress);
    }

    /// @notice Create a new listing
    /// @param _tokenSymbol Symbol of the token listed
    /// @param _tokens The amount of tokens to redeem
    /// @param _price Price of listing per token
    /// should be shifted by 4 decimals (same as MoH token)

    function createNewListing(
        bytes32 _tokenSymbol,
        uint256 _tokens,
        int256 _price
    ) external onlywhitelisted {
        MoTokenManagerFactory factory = MoTokenManagerFactory(
            tokenManagerFactoryAddress
        );
        MoTokenManager manager = MoTokenManager(
            factory.symbolToTokenManager(_tokenSymbol)
        );
        MoToken token = MoToken(manager.token());
        require(
            _tokens <=
                token.balanceOf(msg.sender) -
                    totalTokensListedOf[_tokenSymbol][msg.sender],
            "NT"
        );

        totalTokensListedOf[_tokenSymbol][msg.sender] += _tokens;
        require(
            token.allowance(msg.sender, address(this)) >=
                totalTokensListedOf[_tokenSymbol][msg.sender],
            "NP"
        );

        allListings.push();
        ++listingTail;

        allListings[listingTail].seller = msg.sender;
        allListings[listingTail].listedTokens = _tokens;
        allListings[listingTail].listedPrice = _price;
        allListings[listingTail].tokenSymbol = _tokenSymbol;
        emit CreatedListing(msg.sender, _tokenSymbol, _tokens);
    }

    /// @notice Cancel an existing listing
    /// @param _id listing id

    function cancelListing(uint256 _id) external onlywhitelisted {
        require(
            _id >= listingHead &&
                _id <= listingTail &&
                allListings[_id].seller == msg.sender,
            "NA"
        );

        allListings[_id].listedTokens -= allListings[_id].listedTokensPending;
        totalTokensListedOf[allListings[_id].tokenSymbol][
            msg.sender
        ] -= allListings[_id].listedTokensPending;
        allListings[_id].listedTokensPending = 0;
        emit CancelledListing(msg.sender, _id);
    }

    /// @notice Edit an existing listing
    /// @param _id listing id
    /// @param _tokens update listed tokens to this value

    function editListing(uint256 _id, uint256 _tokens)
        external
        onlywhitelisted
    {
        require(
            _id >= listingHead &&
                _id <= listingTail &&
                allListings[_id].seller == msg.sender &&
                _tokens <=
                allListings[_id].listedTokens -
                    allListings[_id].listedTokensPending,
            "NA"
        );

        totalTokensListedOf[allListings[_id].tokenSymbol][
            msg.sender
        ] -= (allListings[_id].listedTokens - _tokens);
        allListings[_id].listedTokensPending -= (allListings[_id].listedTokens -
            _tokens);
        allListings[_id].listedTokens = _tokens;
        emit EditedListing(msg.sender, _id, _tokens);
    }

    /// @notice Purchase tokens from a given Listing
    /// @param _amount The Fiat amount used for purchase
    /// should be shifted by 4 decimals (same as MoH token)

    function purchaseFromListing(
        uint256 _id,
        uint256 _amount,
        bytes32 _stableCoin
    ) external onlyRWAManager {
        TokenListing storage listing = allListings[_id];
        require(
            _id >= listingHead &&
                _id <= listingTail &&
                listing.listedTokensPending > 0,
            "NA"
        );

        MoTokenManager manager = MoTokenManager(
            MoTokenManagerFactory(tokenManagerFactoryAddress)
                .symbolToTokenManager(listing.tokenSymbol)
        );
        MoToken token = MoToken(manager.token());

        uint256 sellPrice = (
            listing.listedPrice < 0
                ? manager.getNAV()
                : uint256(listing.listedPrice)
        );

        CurrencyOracle currencyOracle = CurrencyOracle(currencyOracleAddress);
        (uint64 stableToFiatConvRate, uint8 decimalsVal) = currencyOracle
            .getFeedLatestPriceAndDecimals(_stableCoin, manager.fiatCurrency());

        uint256 buyStableCoins = (_amount * 10**decimalsVal) /
            stableToFiatConvRate;

        StableCoin(stableCoinAddress).checkForSufficientBalance(
            msg.sender,
            _stableCoin,
            buyStableCoins
        );

        uint256 buyTokens = (_amount * 10**MO_DECIMALS) / sellPrice;

        require(
            token.transferFrom({
                _from: listing.seller,
                _to: msg.sender,
                _amount: buyTokens
            }),
            "TTF"
        );

        IERC20Basic stableCoinContract = IERC20Basic(
            StableCoin(stableCoinAddress).contractAddressOf(_stableCoin)
        );

        require(
            stableCoinContract.transferFrom({
                sender: msg.sender,
                recipient: listing.seller,
                amount: buyStableCoins
            }),
            "STF"
        );

        allListings[_id].listedTokensPending -= buyTokens;
        totalTokensListedOf[listing.tokenSymbol][listing.seller] -= buyTokens;

        for (
            uint256 i = _id;
            allListings[i].listedTokensPending == 0 && i <= listingTail;
            ++i
        ) {
            ++listingHead;
        }

        emit PurchasedFromListing(_id, buyTokens, msg.sender);
    }
}
