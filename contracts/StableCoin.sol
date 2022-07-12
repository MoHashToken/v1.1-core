// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;
import "./interfaces/IERC20Basic.sol";
import "./MoToken.sol";
import "./CurrencyOracle.sol";

/// @title Stable coin manager
/// @notice This handles all stable coin operations related to the token

abstract contract StableCoin {
    /// @dev Mapping points to the address where the stablecoin contract is deployed on chain
    mapping(bytes32 => address) public contractAddressOf;

    /// @dev Mapping points to the pipe address where the stablecoins to be converted to fiat are transferred
    mapping(bytes32 => address) public pipeAddressOf;

    /// @dev Array of all stablecoins added to the contract
    bytes32[] public stableCoinsAssociated;

    /// @dev Address of the associated MoToken
    address public token;

    /// @dev OraclePriceExchange Address contract associated with the stable coin
    address public currencyOracleAddress;

    /// @dev fiatCurrency associated with tokens
    bytes32 public fiatCurrency = "USD";

    event CurrencyOracleAddressSet(address indexed currencyOracleAddress);
    event StableCoinAdded(
        bytes32 indexed symbol,
        address indexed contractAddress,
        address indexed pipeAddress
    );
    event StableCoinDeleted(bytes32 indexed symbol);

    /// @notice Adds a new stablecoin
    /// @dev There can be no duplicate entries for same stablecoin symbol
    /// @param _symbol Stablecoin symbol
    /// @param _contractAddress Stablecoin contract address on chain
    /// @param _pipeAddress Pipe address associated with the stablecoin

    function _addStableCoin(
        bytes32 _symbol,
        address _contractAddress,
        address _pipeAddress
    ) internal {
        require(
            _symbol.length > 0 && contractAddressOf[_symbol] == address(0),
            "SCE"
        );
        contractAddressOf[_symbol] = _contractAddress;
        stableCoinsAssociated.push(_symbol);
        pipeAddressOf[_symbol] = _pipeAddress;
        emit StableCoinAdded(_symbol, _contractAddress, _pipeAddress);
    }

    /// @notice Deletes an existing stablecoin
    /// @param _symbol Stablecoin symbol

    function _deleteStableCoin(bytes32 _symbol) internal {
        require(contractAddressOf[_symbol] != address(0), "NC");
        delete contractAddressOf[_symbol];
        delete pipeAddressOf[_symbol];
        for (uint256 i = 0; i < stableCoinsAssociated.length; i++) {
            if (stableCoinsAssociated[i] == _symbol) {
                stableCoinsAssociated[i] = stableCoinsAssociated[
                    stableCoinsAssociated.length - 1
                ];
                stableCoinsAssociated.pop();
                break;
            }
        }
        emit StableCoinDeleted(_symbol);
    }

    /// @notice Get balance of the stablecoins in the wallet address
    /// @param _symbol Stablecoin symbol
    /// @param _address User address
    /// @return uint Returns the stablecoin balance

    function balanceOf(bytes32 _symbol, address _address)
        public
        view
        returns (uint256)
    {
        IERC20Basic ier = IERC20Basic(contractAddressOf[_symbol]);
        return ier.balanceOf(_address);
    }

    /// @notice Gets the difference between decimals of MoToken and decimals of the stablecoin
    /// @param _symbol Stablecoin symbol
    /// @return uint8 Returns the difference between decimals (0-18)

    function getDecimalsDiff(bytes32 _symbol) public view returns (uint8) {
        return (decimals(token) - decimals(contractAddressOf[_symbol]));
    }

    /// @notice Gets the decimals of the token
    /// @param _tokenAddress Token address on chain
    /// @return uint8 ERC20 decimals() value

    function decimals(address _tokenAddress) internal view returns (uint8) {
        IERC20Basic ier = IERC20Basic(_tokenAddress);
        return ier.decimals();
    }

    /// @notice Gets the total stablecoin balance associated with the MoToken in fiatCurrency
    /// @return balance Stablecoin balance

    function totalBalanceInFiat() public view returns (uint256 balance) {
        CurrencyOracle currencyOracle = CurrencyOracle(currencyOracleAddress);
        for (uint256 i = 0; i < stableCoinsAssociated.length; i++) {
            (uint64 stableToFiatConvRate, uint8 decimalsVal) = currencyOracle
                .getFeedLatestPriceAndDecimals(
                    stableCoinsAssociated[i],
                    fiatCurrency
                );
            uint8 finalDecVale = decimalsVal +
                decimals(contractAddressOf[stableCoinsAssociated[i]]) -
                6;
            balance += ((balanceOf(stableCoinsAssociated[i], token) *
                stableToFiatConvRate) / (10**finalDecVale));
            balance += ((balanceOf(
                stableCoinsAssociated[i],
                pipeAddressOf[stableCoinsAssociated[i]]
            ) * stableToFiatConvRate) / (10**finalDecVale));
        }
    }

    /// @notice Transfers tokens from an external address to the MoToken Address
    /// @param _from Transfer tokens from this address
    /// @param _amount Amount to transfer
    /// @param _symbol Symbol of the tokens to transfer
    /// @return bool Boolean indicating transfer success/failure

    function initiateTransferFrom(
        address _from,
        uint256 _amount,
        bytes32 _symbol
    ) internal returns (bool) {
        require(contractAddressOf[_symbol] != address(0), "NC");
        MoToken moToken = MoToken(token);
        return (
            moToken.receiveStableCoins(
                contractAddressOf[_symbol],
                _from,
                _amount
            )
        );
    }

    /// @notice Transfers tokens from the MoToken address to the stablecoin pipe address
    /// @param _amount Amount to transfer
    /// @param _symbol Symbol of the tokens to transfer
    /// @return bool Boolean indicating transfer success/failure

    function _transferFundsToPipe(bytes32 _symbol, uint256 _amount)
        internal
        returns (bool)
    {
        require(_amount < balanceOf(_symbol, token), "NF");

        MoToken moToken = MoToken(token);
        return (
            moToken.transferStableCoins(
                contractAddressOf[_symbol],
                pipeAddressOf[_symbol],
                _amount
            )
        );
    }
}
