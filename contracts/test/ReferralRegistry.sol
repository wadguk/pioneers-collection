// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IReferralRegistry.sol";

contract ReferralRegistry is IReferralRegistry, AccessControl {
    bytes32 public constant TRUSTED_SIGNER_ROLE = keccak256("TRUSTED_SIGNER_ROLE");
    bytes32 public constant TRUSTED_DAPP_ROLE = keccak256("TRUSTED_DAPP_ROLE");

    uint8 private constant MAX_REFERRAL_LEVEL = 254;
    uint8 private constant NO_REFEREE_FOUND = 255;

    bool public requireCommunityOwner = true;

    mapping(address => Referral) public referrals;
    mapping(address => bool) public communityOwners;

    event ReferralAdded(address dapp, address referrer, address referee);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(TRUSTED_SIGNER_ROLE, _msgSender());
    }

    function addReferral(address referrer, address referee) external onlyRole(TRUSTED_DAPP_ROLE) {
        _addReferral(_msgSender(), referrer, referee);
    }

    function registerOwners(
        address[] memory ownerAddresses
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        for (uint256 i = 0; i < ownerAddresses.length; i++) {
            communityOwners[ownerAddresses[i]] = true;
        }
    }

    function removeOwners(
        address[] memory ownerAddresses
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        for (uint256 i = 0; i < ownerAddresses.length; i++) {
            communityOwners[ownerAddresses[i]] = false;
        }
    }

    function setRequireOwner(bool enable) external onlyRole(TRUSTED_SIGNER_ROLE) {
        requireCommunityOwner = enable;
    }

    function getReferrer(address referee) external view returns (address) {
        return referrals[referee].referrer;
    }

    function getCommunityOwner(address referee) external view returns (address) {
        return referrals[referee].owner;
    }

    function getReferralLevel(address referee) external view returns (uint8) {
        return referrals[referee].level;
    }

    function getRefereeCount(address referrer) external view returns (uint256) {
        return referrals[referrer].referees.length;
    }

    function getReferees(address referrer) external view returns (address[] memory) {
        return referrals[referrer].referees;
    }

    function isReferee(address referee) external view returns (bool) {
        return _isRefereeAssigned(referee);
    }

    function isCommunityOwner(address communityOwner) external view returns (bool) {
        return communityOwners[communityOwner];
    }

    function getReferralTree(address referrer) external view returns (ReferralInfo[] memory) {
        return _getReferralTree(referrer, new ReferralInfo[](0), 0);
    }

    function refereeIsValid(address referrer, address referee) public view returns (bool) {
        return
            referrer != referee &&
            referee != address(0) &&
            referrer != address(0) &&
            referrals[referee].referrer == address(0);
    }

    function getRefereeLevelInReferrerTree(
        address referrer,
        address referee
    ) public view returns (uint8) {
        return _getRefereeLevelInReferrerTree(referrer, referee, 0);
    }

    function _addReferral(address dapp, address referrer, address referee) private {
        require(refereeIsValid(referrer, referee), "Invalid referrer or referee");
        require(referrals[referrer].level < MAX_REFERRAL_LEVEL, "Invalid level");

        if (requireCommunityOwner) {
            require(communityOwners[referrer], "Invalid invite");
            referrals[referee].owner = referrer;
        } else {
            if (!communityOwners[referrer]) {
                require(communityOwners[referrals[referrer].owner], "Invalid invite");
                referrals[referee].owner = referrals[referrer].owner;
            } else {
                referrals[referee].owner = referrer;
            }
        }

        referrals[referrer].referees.push(referee);
        referrals[referee].referrer = referrer;
        referrals[referee].level = referrals[referrer].level + 1;
        emit ReferralAdded(dapp, referrer, referee);
    }

    function _isRefereeAssigned(address referee) private view returns (bool) {
        return referrals[referee].referrer != address(0);
    }

    function _getReferralTree(
        address referrer,
        ReferralInfo[] memory tree,
        uint8 level
    ) private view returns (ReferralInfo[] memory) {
        ReferralInfo[] memory newTree = _expandTree(
            tree,
            ReferralInfo({addr: referrer, level: level})
        );
        address[] memory referees = referrals[referrer].referees;
        for (uint256 i = 0; i < referees.length; i++) {
            newTree = _getReferralTree(referees[i], newTree, level + 1);
        }
        return newTree;
    }

    function _getRefereeLevelInReferrerTree(
        address referrer,
        address referee,
        uint8 level
    ) private view returns (uint8) {
        address[] memory referees = referrals[referrer].referees;
        for (uint256 i = 0; i < referees.length; i++) {
            if (referees[i] == referee) {
                return level + 1;
            }
            uint8 foundLevel = _getRefereeLevelInReferrerTree(
                referees[i],
                referee,
                level + 1
            );
            if (foundLevel != NO_REFEREE_FOUND) {
                return foundLevel;
            }
        }
        return NO_REFEREE_FOUND;
    }

    function _expandTree(
        ReferralInfo[] memory tree,
        ReferralInfo memory newReferral
    ) private pure returns (ReferralInfo[] memory) {
        ReferralInfo[] memory newTree = new ReferralInfo[](tree.length + 1);
        for (uint256 i = 0; i < tree.length; i++) {
            newTree[i] = tree[i];
        }
        newTree[tree.length] = newReferral;
        return newTree;
    }
}