// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./MoTokenManager.sol";
import "./StableCoin.sol";
import "./CurrencyOracle.sol";
import "./access/AccessControlManager.sol";
import "./interfaces/IERC20Basic.sol";
import "./MoTokenManagerFactory.sol";
import "./RWADetails.sol";
import "./MoJuniorTokenManager.sol";

contract RedemptionProcessor {
    /// @dev All assets are stored with 4 decimal shift
    uint8 public constant MO_DECIMALS = 4;

    /// @dev The refund is always issued in a fixed assigned stablecoin
    bytes32 public assignedRefundCoin;

    /// @dev Currency Oracle Address contract associated with the batch processor
    address public currencyOracle;

    /// @dev Implements RWA manager and whitelist access
    address public accessControlManager;

    /// @dev stableCoin Address contract used for stable coin operations
    address public stableCoin;

    /// @dev Exponent of the difference between the decimals of MoToken and assigned refund coin
    int8 public decimalsDiff;

    /// @dev tokenManagerFactoryAddress Address which stores the token manager address for each token
    address public tokenManagerFactoryAddress;

    /// @dev Mapping stores all the tokens symbols and their index in the allTokenRequestsDetails array
    mapping(bytes32 => uint16) public tokenSymbolToId;

    /// @notice This struct holds the request details raised by a user
    struct RedemptionRequest {
        uint256 requestTokens;
        uint256 requestTokensPending;
        address requestor;
    }

    /// @notice This struct holds the all the requests raised till date & mapping of user address to all the requests in RedemptionRequest array
    struct TokenRequestDetails {
        RedemptionRequest[] redemptionRequests;
        mapping(address => uint256[]) addressToRedemptionRequestIndex;
    }

    /// @dev An array of all redemption request details for each token
    TokenRequestDetails[] private allTokenRequestsDetails;

    event AccessControlManagerSet(address indexed accessControlAddress);
    event RefundCoinSet(bytes32 indexed coin);
    event CurrencyOracleAddressSet(address indexed currencyOracle);
    event TokenRequestCreated(uint16 tokenIndex, bytes32 tokenSymbol);
    event RedeemRequestCreated(
        address requestor,
        bytes32 tokenSymbol,
        uint256 requestTokens
    );
    event RedeemRequestCancelled(
        address requestor,
        bytes32 tokenSymbol,
        uint256 index
    );
    event RedeemRequestModified(
        address requestor,
        bytes32 tokenSymbol,
        uint256 newRequestTokens
    );

    constructor(
        address _stableCoin,
        address _accessControlManager,
        address _tokenManagerFactory
    ) {
        stableCoin = _stableCoin;
        assignedRefundCoin = "USDC";
        decimalsDiff =
            int8(MO_DECIMALS) -
            int8(
                IERC20Basic(
                    StableCoin(_stableCoin).contractAddressOf(
                        assignedRefundCoin
                    )
                ).decimals()
            );
        accessControlManager = _accessControlManager;
        tokenManagerFactoryAddress = _tokenManagerFactory;
        allTokenRequestsDetails.push();
        emit AccessControlManagerSet(_accessControlManager);
    }

    /// @notice Access modifier to restrict access only to owner

    modifier onlyOwner() {
        AccessControlManager acm = AccessControlManager(accessControlManager);
        require(acm.isOwner(msg.sender), "NO");
        _;
    }

    /// @notice Access modifier to restrict access only to RWA manager addresses

    modifier onlyRWAManager() {
        AccessControlManager acm = AccessControlManager(accessControlManager);
        require(acm.isRWAManager(msg.sender), "NR");
        _;
    }

    /// @notice Access modifier to restrict access only to whitelisted addresses

    modifier onlywhitelisted() {
        AccessControlManager acm = AccessControlManager(accessControlManager);
        require(acm.isWhiteListed(msg.sender), "NW");
        _;
    }

    /// @notice Setter for setAccessControlManager
    /// @param _accessControlManager Set accessControlManagerAddress to this address

    function setAccessControlManager(address _accessControlManager)
        external
        onlyOwner
    {
        accessControlManager = _accessControlManager;
        emit AccessControlManagerSet(_accessControlManager);
    }

    /// @notice Setter for setTokenManagerFactoryAddress
    /// @param _tokenManagerFactoryAddress Set tokenManagerFactoryAddress to this address

    function setTokenManagerFactoryAddress(address _tokenManagerFactoryAddress)
        external
        onlyOwner
    {
        tokenManagerFactoryAddress = _tokenManagerFactoryAddress;
    }

    /// @notice Setter for assigned refund coin
    /// @param _coin Refund coin symbol

    function setAssignedRefundCoin(bytes32 _coin) external onlyOwner {
        assignedRefundCoin = _coin;
        decimalsDiff =
            int8(MO_DECIMALS) -
            int8(
                IERC20Basic(
                    StableCoin(stableCoin).contractAddressOf(assignedRefundCoin)
                ).decimals()
            );
        emit RefundCoinSet(assignedRefundCoin);
    }

    /// @notice Allows setting currencyOracleAddress
    /// @param _currencyOracle address of the currency oracle

    function setCurrencyOracleAddress(address _currencyOracle)
        external
        onlyOwner
    {
        currencyOracle = _currencyOracle;
        emit CurrencyOracleAddressSet(currencyOracle);
    }

    /// @notice creates request details for a token and stores it in allTokenRequestsDetails array
    /// & stores the token symbol and its index in tokenSymbolToId mapping
    /// @param _tokenSymbol Symbol of the token for which request details are to be created

    function createRequestToTokenMapping(bytes32 _tokenSymbol)
        external
        onlyRWAManager
    {
        require(
            (
                MoTokenManagerFactory(tokenManagerFactoryAddress)
                    .symbolToTokenManager(_tokenSymbol)
            ) != address(0),
            "NTS"
        );
        allTokenRequestsDetails.push();
        uint16 tokenIndex = uint8(allTokenRequestsDetails.length - 1);
        tokenSymbolToId[_tokenSymbol] = tokenIndex;
        emit TokenRequestCreated(tokenIndex, _tokenSymbol);
    }

    /// @notice Creates a request for a token for a user for a given amount of tokens
    /// & stores the request details in allTokenRequestsDetails array
    /// @param _tokenSymbol Symbol of the token for which request details are to be created
    /// @param _requestTokens Amount of tokens to be requested

    function createRedeemRequest(bytes32 _tokenSymbol, uint256 _requestTokens)
        external
        onlywhitelisted
    {
        uint16 tokenIndex = tokenSymbolToId[_tokenSymbol];
        require(tokenIndex != 0, "NTS");
        require(!hasToken(_tokenSymbol, msg.sender, _requestTokens), "IN");
        require(isRedemptionAllowed(_tokenSymbol), "IN");

        TokenRequestDetails
            storage tokenRequestDetails = allTokenRequestsDetails[tokenIndex];
        tokenRequestDetails.redemptionRequests.push(
            RedemptionRequest(_requestTokens, _requestTokens, msg.sender)
        );

        tokenRequestDetails.addressToRedemptionRequestIndex[msg.sender].push(
            uint256(tokenRequestDetails.redemptionRequests.length - 1)
        );
        address tokenManagerAddress = MoTokenManagerFactory(
            tokenManagerFactoryAddress
        ).symbolToTokenManager(_tokenSymbol);

        MoTokenManager manager = MoTokenManager(tokenManagerAddress);

        require(
            MoToken(manager.token()).receiveTokens(msg.sender, _requestTokens),
            "RTOF"
        );
        emit RedeemRequestCreated(msg.sender, _tokenSymbol, _requestTokens);
    }

    /// @notice Modifies a request for a token for a user for a given amount of tokens
    /// & updates the request details in allTokenRequestsDetails array
    /// @param _tokenSymbol Symbol of the token for which request details are to be modified
    /// @param _requestTokens Amount of tokens to be updated in the request

    function modifyRedeemRequest(
        bytes32 _tokenSymbol,
        uint256 index,
        uint256 _requestTokens
    ) external onlywhitelisted {
        uint16 tokenIndex = tokenSymbolToId[_tokenSymbol];
        require(tokenIndex != 0, "NTS");

        TokenRequestDetails
            storage tokenRequestDetails = allTokenRequestsDetails[tokenIndex];

        RedemptionRequest storage redemptionRequest = tokenRequestDetails
            .redemptionRequests[index];
        require(
            redemptionRequest.requestor == msg.sender &&
                redemptionRequest.requestTokensPending > 0,
            "IN"
        );
        address tokenManagerAddress = MoTokenManagerFactory(
            tokenManagerFactoryAddress
        ).symbolToTokenManager(_tokenSymbol);

        MoTokenManager manager = MoTokenManager(tokenManagerAddress);

        require(redemptionRequest.requestTokensPending > _requestTokens, "IN");
        require(
            MoToken(manager.token()).transferTokens(
                msg.sender,
                redemptionRequest.requestTokensPending - _requestTokens
            ),
            "TTOF"
        );

        if (_requestTokens == 0) {
            redemptionRequest.requestTokensPending = 0;
            emit RedeemRequestCancelled(msg.sender, _tokenSymbol, index);
            return;
        }

        redemptionRequest.requestTokensPending = _requestTokens;
        emit RedeemRequestModified(msg.sender, _tokenSymbol, _requestTokens);
    }

    /// @notice fulfill a request for a token symbol for a user for a given amount of stable coin
    /// & updates the request details in allTokenRequestsDetails array
    /// @param _tokenSymbol Symbol of the token for which request details are to be fulfilled
    /// @param _index Index of the request to be fulfilled
    /// @param _amount Amount is in fiat curreny with motoken decimals shifted

    function fulfill(
        bytes32 _tokenSymbol,
        uint256 _index,
        uint256 _amount
    ) external onlyRWAManager {
        require(uint16(tokenSymbolToId[_tokenSymbol]) != uint16(0), "NTS");
        require(isRedemptionAllowed(_tokenSymbol), "IN");

        TokenRequestDetails
            storage tokenRequestDetails = allTokenRequestsDetails[
                uint16(tokenSymbolToId[_tokenSymbol])
            ];

        require(_index < tokenRequestDetails.redemptionRequests.length, "IN");

        RedemptionRequest storage request = tokenRequestDetails
            .redemptionRequests[_index];

        if (request.requestTokensPending == 0) {
            return;
        }

        address tokenManagerAddress = MoTokenManagerFactory(
            tokenManagerFactoryAddress
        ).symbolToTokenManager(_tokenSymbol);

        MoTokenManager manager = MoTokenManager(tokenManagerAddress);

        uint256 refundTokens = (_amount * 10**MO_DECIMALS) / (manager.getNAV());
        uint256 refundAmount = _amount;

        if (refundTokens > request.requestTokensPending) {
            refundTokens = request.requestTokensPending;
            refundAmount =
                (refundTokens * (manager.getNAV())) /
                10**MO_DECIMALS;
            request.requestTokensPending = 0;
        } else {
            request.requestTokensPending -= refundTokens;
        }

        (uint64 stableToFiatConvRate, uint8 decimalsVal) = CurrencyOracle(
            currencyOracle
        ).getFeedLatestPriceAndDecimals(
                assignedRefundCoin,
                manager.fiatCurrency()
            );

        if (decimalsDiff > -1) {
            refundAmount =
                (refundAmount * 10**decimalsVal) /
                10**uint8(decimalsDiff) /
                stableToFiatConvRate;
        } else {
            refundAmount =
                (refundAmount * 10**decimalsVal * 10**uint8(-decimalsDiff)) /
                stableToFiatConvRate;
        }

        StableCoin(stableCoin).checkForSufficientBalance(
            manager.token(),
            assignedRefundCoin,
            refundAmount
        );

        require(
            _transferStableCoins(
                request.requestor,
                refundAmount,
                tokenManagerAddress
            ),
            "TSOF"
        );
        MoToken(manager.token()).burn(refundTokens, manager.token());
    }

    /// @notice Gets the total request count for a token symbol
    /// @param _tokenSymbol Symbol of the token for which request count is to be retrieved
    /// @return totalRequest count for the token symbol

    function getTotalRequest(bytes32 _tokenSymbol)
        external
        view
        onlyRWAManager
        returns (uint256 totalRequest)
    {
        uint16 tokenIndex = tokenSymbolToId[_tokenSymbol];
        require(tokenIndex != 0, "NTS");
        TokenRequestDetails
            storage tokenRequestDetails = allTokenRequestsDetails[tokenIndex];

        totalRequest = tokenRequestDetails.redemptionRequests.length;
    }

    /// @notice Gets the request details for a token symbol by index
    /// @param _tokenSymbol Symbol of the token for which request details are to be retrieved
    /// @param _requestId Index of the request details to be retrieved
    /// @return requestTokens Requested tokens for a request
    /// @return requestTokensPending Requested tokens pending for a request
    /// @return requestor address of a requestor for a request

    function getRequestDetailsById(bytes32 _tokenSymbol, uint256 _requestId)
        external
        view
        onlywhitelisted
        returns (
            uint256 requestTokens,
            uint256 requestTokensPending,
            address requestor
        )
    {
        uint16 tokenIndex = tokenSymbolToId[_tokenSymbol];
        require(tokenIndex != 0, "NTS");
        TokenRequestDetails
            storage tokenRequestDetails = allTokenRequestsDetails[tokenIndex];
        RedemptionRequest memory redemptionRequest = tokenRequestDetails
            .redemptionRequests[_requestId];
        return (
            redemptionRequest.requestTokens,
            redemptionRequest.requestTokensPending,
            redemptionRequest.requestor
        );
    }

    /// @notice Gets the request details for a token symbol by user address
    /// @param _tokenSymbol Symbol of the token for which request details are to be retrieved
    /// @param _requestor Address of the user for which request details are to be retrieved
    /// @return length Length of the array of request details for a user

    function getRedemptionRequestDetailsByAddress(
        bytes32 _tokenSymbol,
        address _requestor
    ) external view onlywhitelisted returns (uint256 length) {
        uint16 tokenIndex = tokenSymbolToId[_tokenSymbol];
        require(tokenIndex != 0, "NTS");
        TokenRequestDetails
            storage tokenRequestDetails = allTokenRequestsDetails[tokenIndex];
        length = tokenRequestDetails
            .addressToRedemptionRequestIndex[_requestor]
            .length;
    }

    /// @notice Initiates stablecoin transfer for refund
    /// @param _to User address who is to be issued refund
    /// @param _amount Stablecoin amount to be refunded
    /// @param _tokenManagerAddress address of token manager related to the token symbol
    /// @return true if transfer is successful, false otherwise

    function _transferStableCoins(
        address _to,
        uint256 _amount,
        address _tokenManagerAddress
    ) internal returns (bool) {
        MoTokenManager manager = MoTokenManager(_tokenManagerAddress);
        require(
            _amount <=
                StableCoin(stableCoin).balanceOf(
                    assignedRefundCoin,
                    manager.token()
                ),
            "NF"
        );

        MoToken token = MoToken(manager.token());
        return (
            token.transferStableCoins(
                StableCoin(stableCoin).contractAddressOf(assignedRefundCoin),
                _to,
                _amount
            )
        );
    }

    /// @notice Checks if the give user address as amount of tokens for a token symbol.
    /// @param _tokenSymbol Symbol of the token for which balance is to be checked
    /// @param _address Address of the user for which balance is to be checked
    /// @param _amount Amount of tokens to be checked
    /// @return true if the user has sufficient balance, false otherwise

    function hasToken(
        bytes32 _tokenSymbol,
        address _address,
        uint256 _amount
    ) internal view returns (bool) {
        address tokenManagerAddress = MoTokenManagerFactory(
            tokenManagerFactoryAddress
        ).symbolToTokenManager(_tokenSymbol);
        MoToken token = MoToken(MoTokenManager(tokenManagerAddress).token());
        return token.balanceOf(_address) >= _amount;
    }

    /// @notice Checks if redemption is allowed for a token symbol.
    /// @param _tokenSymbol Symbol of the token for which redemption is to be checked
    /// @return true if redemption is allowed, false otherwise

    function isRedemptionAllowed(bytes32 _tokenSymbol)
        internal
        view
        returns (bool)
    {
        bytes32 tokenSymbol = MoTokenManagerFactory(tokenManagerFactoryAddress)
            .linkedSrTokenOf(_tokenSymbol);

        address tokenManagerAddress = MoTokenManagerFactory(
            tokenManagerFactoryAddress
        ).symbolToTokenManager(tokenSymbol);
        if (tokenManagerAddress == address(0)) {
            return true;
        }

        address manager = MoTokenManagerFactory(tokenManagerFactoryAddress)
            .symbolToTokenManager(_tokenSymbol);
        MoJuniorTokenManager tokenManager = MoJuniorTokenManager(manager);
        RWADetails rwaDetails = RWADetails(tokenManager.rWADetails());
        return rwaDetails.isRedemptionAllowed(tokenManager.linkedSrRwaUnitId());
    }
}
