// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract USDC is ERC20PresetFixedSupply {
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        address _owner
    ) ERC20PresetFixedSupply(_name, _symbol, _initialSupply, _owner) {
        // DO NOTHING
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
