// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract AccessControlManager is AccessControl  {

    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
    bytes32 public constant RWA_MANAGER_ROLE = keccak256("RWA_MANAGER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    constructor(){
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setRoleAdmin(WHITELIST_ROLE, ADMIN_ROLE);
        _setRoleAdmin(RWA_MANAGER_ROLE, ADMIN_ROLE);
    }

    function isWhiteListed(address account) external view returns (bool) {
        return hasRole(WHITELIST_ROLE, account);
    }

    function isRWAManager(address account) external view returns (bool) {
        return hasRole(RWA_MANAGER_ROLE, account);
    }

    function isAdmin(address account) external view returns (bool) {
        return hasRole(ADMIN_ROLE, account);
    }

}