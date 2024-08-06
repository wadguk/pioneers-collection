// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IReferralRegistry {
    struct Referral {
        address owner;
        address referrer;
        address[] referees;
        uint8 level;
    }

    struct ReferralInfo {
        address addr;
        uint8 level;
    }

    function addReferral(address referrer, address referee) external;
    
    function getReferrer(address referee) external view returns (address);
    
    function getCommunityOwner(address referee) external view returns (address);

    function getReferralLevel(address referee) external view returns (uint8);
    
    function getRefereeCount(address referrer) external view returns (uint256);
    
    function getReferees(address referrer) external view returns (address[] memory);
    
    function isReferee(address referee) external view returns (bool);
    
    function isCommunityOwner(address communityOwner) external view returns (bool);

    function getReferralTree(address referrer) external view returns (ReferralInfo[] memory);
    
    function getRefereeLevelInReferrerTree(address referrer, address referee) external view returns (uint8);
    
    function refereeIsValid(address referrer, address referee) external view returns (bool);
    
}