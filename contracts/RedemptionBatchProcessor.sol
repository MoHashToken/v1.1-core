// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;
import "./MoTokenManager.sol";
import "./StableCoin.sol";
import "./CurrencyOracle.sol";
import "./access/AccessControlManager.sol";
import "./interfaces/IERC20Basic.sol";

/// @title Token Redemption Batch Processor
/// @notice This contract handles the token redemption process

contract RedemptionBatchProcessor {
    /// @dev All assets are stored with 4 decimal shift
    uint8 public constant MO_DECIMALS = 4;

    /// @notice This struct holds the request details raised by a user

    struct RedemptionRequest {
        uint256 requestTokens;
        uint256 requestTokensPending;
    }

    /// notice This struct holds all the details regarding a redemption batch

    struct Batch {
        mapping(address => RedemptionRequest) requests;
        address[] userList;
        uint256 batchTokensPending;
    }

    /// @dev An array of all the Batch instances created till date
    Batch[] private allBatches;

    /// @dev Index of the batches which are yet to be fulfilled
    uint256 public batchHead;

    /// @dev Index beyond the latest batch
    uint256 public batchTail;

    /// @dev Token manager contract associated with the batch processor
    address public tokenManagerAddress;

    /// @dev The refund is always issued in a fixed assigned stablecoin
    bytes32 public assignedRefundCoin;

    /// @dev Assigned fiat currency for the token
    bytes32 public fiatCurrency = "USD";

    /// @dev Exponent of the difference between the decimals of MoToken and assigned refund coin
    int8 public decimalsDiff;

    /// @dev Currency Oracle Address contract associated with the batch processor
    address public currencyOracleAddress;

    /// @dev Implements RWA manager and whitelist access
    address public accessControlManagerAddress;

    /// @dev stableCoin Address contract used for stable coin operations
    address public stableCoinAddress;

    event BatchCreated(uint256 indexed id, address indexed creator);
    event RedeemRequestCreated(address indexed user, uint256 indexed tokens);
    event RedeemRequestCancelled(address indexed user, uint256 indexed batchId);
    event BatchFulfilled(
        uint256 indexed id,
        uint256 indexed tokens,
        bool indexed closed
    );
    event CurrencyOracleAddressSet(address indexed currencyOracleAddress);
    event RefundCoinSet(bytes32 indexed coin);
    event FiatCurrencySet(bytes32 indexed currency);
    event AccessControlManagerSet(address indexed accessControlAddress);

    /// @notice Constructor initializes token manager
    /// @dev In addition to the above, the constructor is also assigning USDC as default refund coin
    /// @param _tokenManager Token manager address

    constructor(
        address _tokenManager,
        address _stableCoin,
        address _accessControlManager
    ) {
        tokenManagerAddress = _tokenManager;
        stableCoinAddress = _stableCoin;
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

    /// @notice Setter for assigned refund coin
    /// @param _coin Refund coin symbol

    function setAssignedRefundCoin(bytes32 _coin) external onlyOwner {
        assignedRefundCoin = _coin;
        decimalsDiff =
            int8(MO_DECIMALS) -
            int8(
                IERC20Basic(
                    StableCoin(stableCoinAddress).contractAddressOf(
                        assignedRefundCoin
                    )
                ).decimals()
            );
        emit RefundCoinSet(assignedRefundCoin);
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

    /// @notice Allows setting fiatCurrecy
    /// @param _fiatCurrency fiatCureency

    function setFiatCurrency(bytes32 _fiatCurrency) external onlyOwner {
        fiatCurrency = _fiatCurrency;
        emit FiatCurrencySet(fiatCurrency);
    }

    /// @notice Creates a new batch

    function createBatch() external onlyRWAManager {
        allBatches.push();
        batchTail++;
        emit BatchCreated(batchTail, msg.sender);
    }

    /// @notice Close all the completed batches

    function closeBatches() internal {
        while (
            batchHead < batchTail &&
            allBatches[batchHead].batchTokensPending == 0
        ) {
            batchHead++;
        }
    }

    /// @notice Create a new redeem request in the current batch
    /// @param _tokens The amount of tokens to redeem

    function createRedeemRequest(uint256 _tokens) external onlywhitelisted {
        require(
            batchTail > batchHead &&
                _tokens > 0 &&
                allBatches[batchTail - 1]
                    .requests[msg.sender]
                    .requestTokensPending ==
                0,
            "NA"
        );

        MoTokenManager manager = MoTokenManager(tokenManagerAddress);
        MoToken token = MoToken(manager.token());
        require(token.balanceOf(msg.sender) >= _tokens, "NT");

        if (allBatches[batchTail - 1].requests[msg.sender].requestTokens == 0) {
            allBatches[batchTail - 1].requests[msg.sender] = RedemptionRequest(
                0,
                0
            );
            allBatches[batchTail - 1].userList.push(msg.sender);
        }

        allBatches[batchTail - 1].requests[msg.sender].requestTokens = _tokens;
        allBatches[batchTail - 1]
            .requests[msg.sender]
            .requestTokensPending = _tokens;
        allBatches[batchTail - 1].batchTokensPending =
            allBatches[batchTail - 1].batchTokensPending +
            _tokens;

        emit RedeemRequestCreated(msg.sender, _tokens);

        require(token.receiveTokens(msg.sender, _tokens), "RTOF");
    }

    /// @notice Cancel an existing redeem in the given batch
    /// @param _id Batch id where the redeem request is to be cancelled

    function cancelRedeemRequest(uint256 _id) external {
        require(
            allBatches[_id].requests[msg.sender].requestTokensPending > 0,
            "NR"
        );

        allBatches[_id].batchTokensPending =
            allBatches[_id].batchTokensPending -
            allBatches[_id].requests[msg.sender].requestTokensPending;

        uint256 requestTokensPending = allBatches[_id]
            .requests[msg.sender]
            .requestTokensPending;
        allBatches[_id].requests[msg.sender].requestTokensPending = 0;

        emit RedeemRequestCancelled(msg.sender, _id);

        MoTokenManager manager = MoTokenManager(tokenManagerAddress);
        MoToken token = MoToken(manager.token());

        require(token.transferTokens(msg.sender, requestTokensPending), "TTOF");
    }

    /// @notice Fulfill the redeem requests in the given batch
    /// @param _id Batch Id
    /// @param _amount The Fiat amount which is used to issue refunds,
    /// should be shifted by 4 decimals (same as mo token)

    function fulfillBatch(uint256 _id, uint256 _amount)
        external
        onlyRWAManager
    {
        if (allBatches[_id].batchTokensPending == 0) {
            closeBatches();
            return;
        }
        require(_id >= batchHead, "BD");

        MoTokenManager manager = MoTokenManager(tokenManagerAddress);
        MoToken token = MoToken(manager.token());

        uint256 nav = uint256(manager.getNAV());
        uint256 refundTokens = (_amount * 10**MO_DECIMALS) / nav;

        if (refundTokens > allBatches[_id].batchTokensPending)
            refundTokens = allBatches[_id].batchTokensPending;

        CurrencyOracle currencyOracle = CurrencyOracle(currencyOracleAddress);
        (uint64 stableToFiatConvRate, uint8 decimalsVal) = currencyOracle
            .getFeedLatestPriceAndDecimals(assignedRefundCoin, fiatCurrency);

        // ensure sufficient balance
        if (decimalsDiff >= 0) {
            StableCoin(stableCoinAddress).checkForSufficientBalance(
                manager.token(),
                assignedRefundCoin,
                (_amount * 10**decimalsVal) /
                    10**uint8(decimalsDiff) /
                    stableToFiatConvRate
            );
        } else {
            StableCoin(stableCoinAddress).checkForSufficientBalance(
                manager.token(),
                assignedRefundCoin,
                (_amount * 10**decimalsVal * 10**uint8(-decimalsDiff)) /
                    stableToFiatConvRate
            );
        }

        if (refundTokens == allBatches[_id].batchTokensPending) {
            for (
                uint256 itr = 0;
                itr < allBatches[_id].userList.length;
                itr++
            ) {
                address user = allBatches[_id].userList[itr];

                RedemptionRequest storage request = allBatches[_id].requests[
                    user
                ];

                // refund amount in fiat
                uint256 refundAmount = (request.requestTokensPending * nav);
                if (
                    decimalsDiff >= 0 || (int8(MO_DECIMALS) + decimalsDiff) >= 0
                )
                    refundAmount =
                        refundAmount /
                        10**uint8(int8(MO_DECIMALS) + decimalsDiff);
                else
                    refundAmount =
                        refundAmount *
                        10**(uint8(-decimalsDiff) - MO_DECIMALS);

                // refund amount in stable coins
                refundAmount =
                    (refundAmount * (10**decimalsVal)) /
                    stableToFiatConvRate;
                require(_transferStableCoins(user, refundAmount), "TSOF");
                token.burn(request.requestTokensPending, manager.token());
                request.requestTokensPending = 0;
            }

            allBatches[_id].batchTokensPending = 0;
            closeBatches();
            emit BatchFulfilled(_id, refundTokens, true);
        } else {
            for (
                uint256 itr = 0;
                itr < allBatches[_id].userList.length;
                itr++
            ) {
                address user = allBatches[_id].userList[itr];
                uint256 userRefund = (allBatches[_id]
                    .requests[user]
                    .requestTokensPending * refundTokens) /
                    allBatches[_id].batchTokensPending;
                // refund amount in fiat
                uint256 refundAmount = (userRefund * nav);
                if (
                    decimalsDiff >= 0 || (int8(MO_DECIMALS) + decimalsDiff) >= 0
                )
                    refundAmount =
                        refundAmount /
                        10**uint8(int8(MO_DECIMALS) + decimalsDiff);
                else
                    refundAmount =
                        refundAmount *
                        10**(uint8(-decimalsDiff) - MO_DECIMALS);

                // refund amount in stable coins
                refundAmount =
                    (refundAmount * (10**decimalsVal)) /
                    stableToFiatConvRate;
                allBatches[_id].requests[user].requestTokensPending =
                    allBatches[_id].requests[user].requestTokensPending -
                    userRefund;
                require(_transferStableCoins(user, refundAmount), "TSOF");
                token.burn(userRefund, manager.token());
            }
            allBatches[_id].batchTokensPending =
                allBatches[_id].batchTokensPending -
                refundTokens;
            emit BatchFulfilled(_id, refundTokens, false);
        }
    }

    /// @notice Getter for all the users who have raised redemption request
    /// @param _id Batch Id
    /// @return userList Array of all the users who have raised redemption request

    function getBatchUsers(uint256 _id)
        external
        view
        returns (address[] memory userList)
    {
        return (allBatches[_id].userList);
    }

    /// @notice Getter for Request details
    /// @param _id Batch Id
    /// @param _user Address of user who has raised the redemption request
    /// @return request Total requested amount
    /// @return pending Requested amount pending

    function getBatchRequestDetails(uint256 _id, address _user)
        external
        view
        returns (uint256 request, uint256 pending)
    {
        return (
            allBatches[_id].requests[_user].requestTokens,
            allBatches[_id].requests[_user].requestTokensPending
        );
    }

    /// @notice Getter for tokens pending redemption in the whole batch
    /// @param _id Batch Id
    /// @return tokens Amount of tokens pending

    function getBatchTokensPending(uint256 _id)
        external
        view
        returns (uint256 tokens)
    {
        return (allBatches[_id].batchTokensPending);
    }

    /// @notice User can call this function to get total amount of tokens locked for redemption
    /// @return _tokens Amount of tokens locked

    function getLockedTokens() external view returns (uint256 _tokens) {
        for (uint256 id = batchHead; id < batchTail; id++) {
            _tokens =
                _tokens +
                allBatches[id].requests[msg.sender].requestTokensPending;
        }
    }

    /// @notice Initiates stablecoin transfer for refund
    /// @param _to User address who is to be issued refund
    /// @param _amount Stablecoin amount to be refunded
    /// @return bool Stablecoins transfer success/fail

    function _transferStableCoins(address _to, uint256 _amount)
        internal
        returns (bool)
    {
        MoTokenManager manager = MoTokenManager(tokenManagerAddress);
        require(
            _amount <=
                StableCoin(stableCoinAddress).balanceOf(
                    assignedRefundCoin,
                    manager.token()
                ),
            "NF"
        );

        MoToken token = MoToken(manager.token());
        return (
            token.transferStableCoins(
                StableCoin(stableCoinAddress).contractAddressOf(
                    assignedRefundCoin
                ),
                _to,
                _amount
            )
        );
    }
}
